require 'rails_helper'

describe Conversations::AssignmentService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#perform' do
    context 'when assignee_id is blank' do
      before do
        conversation.update!(assignee: agent, ai_assignee: agent_bot)
      end

      it 'clears both human and bot assignees' do
        described_class.new(conversation: conversation, assignee_id: nil).perform

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_agent_bot_id).to be_nil
        expect(conversation.ai_assignee_type).to be_nil
      end

      it 'preserves conversation status' do
        conversation.update!(status: :snoozed, snoozed_until: 1.day.from_now)

        described_class.new(conversation: conversation, assignee_id: nil).perform

        expect(conversation.reload.status).to eq('snoozed')
      end
    end

    context 'when assigning a user' do
      before do
        conversation.update!(ai_assignee: agent_bot, assignee: nil, status: :pending)
      end

      it 'sets the agent, clears agent bot and opens the conversation' do
        result = described_class.new(conversation: conversation, assignee_id: agent.id).perform

        conversation.reload
        expect(result).to eq(agent)
        expect(conversation.assignee_id).to eq(agent.id)
        expect(conversation.assignee_agent_bot_id).to be_nil
        expect(conversation.ai_assignee_type).to be_nil
        expect(conversation.status).to eq('open')
      end

      it 'starts the waiting clock when opening a bot-owned pending conversation' do
        conversation.update!(waiting_since: nil)

        freeze_time do
          described_class.new(conversation: conversation, assignee_id: agent.id).perform

          expect(conversation.reload.waiting_since).to eq(Time.current)
        end
      end

      it 'preserves status for ordinary human assignment changes' do
        conversation.update!(ai_assignee: nil, status: :resolved)

        described_class.new(conversation: conversation, assignee_id: agent.id).perform

        expect(conversation.reload.status).to eq('resolved')
      end

      it 'preserves status when taking over a bot-owned non-pending conversation' do
        conversation.update!(ai_assignee: agent_bot, status: :resolved)

        described_class.new(conversation: conversation, assignee_id: agent.id).perform

        expect(conversation.reload.status).to eq('resolved')
      end
    end

    context 'when assigning an agent bot' do
      let(:service) do
        described_class.new(
          conversation: conversation,
          assignee_id: agent_bot.id,
          assignee_type: 'AgentBot'
        )
      end

      before do
        create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)
      end

      it 'sets the agent bot, clears human assignee and marks the conversation pending' do
        conversation.update!(assignee: agent, ai_assignee: nil, status: :open)

        result = service.perform

        conversation.reload
        expect(result).to eq(agent_bot)
        expect(conversation.assignee_agent_bot_id).to eq(agent_bot.id)
        expect(conversation.ai_assignee_type).to eq('AgentBot')
        expect(conversation.assignee_id).to be_nil
        expect(conversation.status).to eq('pending')
      end

      it 'marks a resolved conversation pending' do
        conversation.update!(status: :resolved)

        service.perform

        expect(conversation.reload.status).to eq('pending')
      end

      it 'marks a snoozed conversation pending and clears the snooze timestamp' do
        conversation.update!(status: :snoozed, snoozed_until: 1.day.from_now)

        service.perform

        conversation.reload
        expect(conversation.status).to eq('pending')
        expect(conversation.snoozed_until).to be_nil
      end
    end

    context 'when an agent assigns the agent bot' do
      let(:assigner) { create(:user, account: account, name: 'Assigner') }

      before do
        create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)
        Current.user = assigner
      end

      after { Current.reset }

      def activity_contents
        ActiveJob::Base.queue_adapter.enqueued_jobs
                       .select { |job| job['job_class'] == 'Conversations::ActivityMessageJob' }
                       .map { |job| job['arguments'].second['content'] }
      end

      it 'writes that the agent assigned the bot, instead of an unassignment, when the bot replaces a human' do
        conversation.update!(assignee: agent, ai_assignee: nil, status: :open)
        clear_enqueued_jobs

        described_class.new(conversation: conversation, assignee_id: agent_bot.id, assignee_type: 'AgentBot').perform

        expect(activity_contents).to include("Assigned to #{agent_bot.name} by #{assigner.name}")
        expect(activity_contents).not_to include("Conversation unassigned by #{assigner.name}")
      end

      it 'writes the handover when the inbox bot takes a conversation stuck with another bot' do
        stuck_with = create(:agent_bot, account: account, name: 'Foreign bot')
        conversation.update!(assignee: nil, ai_assignee: stuck_with, status: :pending)
        clear_enqueued_jobs

        described_class.new(conversation: conversation, assignee_id: agent_bot.id, assignee_type: 'AgentBot').perform

        expect(conversation.reload.ai_assignee).to eq(agent_bot)
        expect(activity_contents).to include("Assigned to #{agent_bot.name} by #{assigner.name}")
      end

      it 'still writes the user assignment when an agent takes the conversation from the bot' do
        conversation.update!(assignee: nil, ai_assignee: agent_bot, status: :pending)
        clear_enqueued_jobs

        described_class.new(conversation: conversation, assignee_id: agent.id).perform

        expect(activity_contents).to include("Assigned to #{agent.name} by #{assigner.name}")
      end

      it 'writes nothing about the bot when the inbox hands it a new conversation' do
        clear_enqueued_jobs

        create(:conversation, account: account, inbox: conversation.inbox)

        expect(activity_contents.grep(/#{Regexp.escape(agent_bot.name)}/)).to be_empty
      end
    end

    # A bot owns only the conversations of the inbox it serves (#721): any other bot of the account
    # would take the conversation out of the team's queues without ever answering it.
    context 'when the agent bot does not serve the conversation inbox' do
      let(:other_inbox) { create(:inbox, account: account) }
      let(:foreign_bot) { create(:agent_bot, account: account) }

      before do
        create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)
        conversation.update!(assignee: agent, ai_assignee: nil, status: :open)
      end

      def assign(bot)
        described_class.new(conversation: conversation, assignee_id: bot.id, assignee_type: 'AgentBot').perform
      end

      def expect_conversation_untouched
        conversation.reload
        expect(conversation.assignee_id).to eq(agent.id)
        expect(conversation.assignee_agent_bot_id).to be_nil
        expect(conversation.ai_assignee_type).to be_nil
        expect(conversation.status).to eq('open')
      end

      it 'refuses a bot that serves another inbox' do
        create(:agent_bot_inbox, inbox: other_inbox, agent_bot: foreign_bot)

        expect(assign(foreign_bot)).to be_nil
        expect_conversation_untouched
      end

      it 'refuses a bot of the account that serves no inbox' do
        expect(assign(foreign_bot)).to be_nil
        expect_conversation_untouched
      end

      it 'refuses a bot that only observes the conversation inbox' do
        create(:agent_bot_observer, inbox: conversation.inbox, agent_bot: foreign_bot)

        expect(assign(foreign_bot)).to be_nil
        expect_conversation_untouched
      end

      it 'refuses the inbox bot while its connection is inactive' do
        conversation.inbox.agent_bot_inbox.update!(status: :inactive)

        expect(assign(agent_bot)).to be_nil
        expect_conversation_untouched
      end
    end
  end
end
