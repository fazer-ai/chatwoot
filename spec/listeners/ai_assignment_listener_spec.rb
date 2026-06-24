require 'rails_helper'

RSpec.describe AiAssignmentListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:ia_user) { create(:user, account: account, name: 'IA | Auris') }
  let(:agent) { create(:user, account: account) }
  let(:team) { create(:team, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, assignee: agent) }
  let(:event) { Events::Base.new('team.changed', Time.zone.now, conversation: conversation) }

  before do
    # `Current` uses ActiveSupport::CurrentAttributes (thread-local).
    # RSpec doesn't reset it between examples, so a leftover value from
    # a previous spec can pollute fixture creation here and make the
    # real AssignmentHandler dispatch path call this listener with
    # Current.user already pointed at the IA — creating an extra
    # attempt that taints the assertions below.
    Current.reset
    create(:team_member, team: team, user: agent)
    conversation
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
      agent.id.to_s => 'online'
    )
  end

  describe '#team_changed' do
    # The whole point of the listener: capture WHO from the team was
    # online at the exact moment the IA tried to hand off, so the audit
    # can flag when the assigned agent wasn't actually online.
    it 'creates an AiAssignmentAttempt when the trigger user is the IA' do
      Current.user = ia_user
      expect { listener.team_changed(event) }
        .to change(AiAssignmentAttempt, :count).by(1)

      attempt = AiAssignmentAttempt.last
      expect(attempt.conversation).to eq(conversation)
      expect(attempt.team).to eq(team)
      expect(attempt.agent_assigned_id).to eq(agent.id)
      expect(attempt.triggered_by_id).to eq(ia_user.id)
      expect(attempt.online_user_ids).to eq([agent.id])
    end

    # Manual assignments (operator → operator) are out of scope for this
    # report by design: the audit only measures IA-driven assignments.
    it 'does NOT create an attempt for a manual assignment' do
      Current.user = create(:user, name: 'Maria')
      expect { listener.team_changed(event) }
        .not_to change(AiAssignmentAttempt, :count)
    end

    it 'records empty online set when nobody in the team is online' do
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
      Current.user = ia_user

      listener.team_changed(event)
      expect(AiAssignmentAttempt.last.online_user_ids).to eq([])
    end

    # `busy` counts as a valid handoff target — agent is logged in,
    # auto-assigner could still route to them.
    it 'counts busy agents as online' do
      another = create(:user, account: account)
      create(:team_member, team: team, user: another)
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
        agent.id.to_s => 'online',
        another.id.to_s => 'busy'
      )
      Current.user = ia_user

      listener.team_changed(event)
      expect(AiAssignmentAttempt.last.online_user_ids).to contain_exactly(agent.id, another.id)
    end

    # The audit is best-effort: a failure here must never bubble up and
    # 500 the assignment endpoint the operator hit.
    it 'swallows errors so the assignment is never blocked' do
      Current.user = ia_user
      allow(OnlineStatusTracker).to receive(:get_available_users).and_raise(Redis::CannotConnectError)

      expect { listener.team_changed(event) }.not_to raise_error
      expect { listener.team_changed(event) }.not_to change(AiAssignmentAttempt, :count)
    end

    it 'skips when team_id is blank (team was unassigned, not reassigned)' do
      conversation.update!(team: nil)
      Current.user = ia_user

      expect { listener.team_changed(event) }
        .not_to change(AiAssignmentAttempt, :count)
    end
  end
end
