require 'rails_helper'

RSpec.describe 'Conversation Assignment API', type: :request do
  let(:account) { create(:account) }

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/assignments' do
    let(:conversation) { create(:conversation, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated bot with out access to the inbox' do
      let(:agent_bot) { create(:agent_bot) }
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
             headers: { api_access_token: agent_bot.access_token.token },
             params: {
               assignee_id: agent.id
             },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to the inbox' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:agent_bot) { create(:agent_bot, account: account) }
      let(:team) { create(:team, account: account) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'assigns a user to the conversation' do
        params = { assignee_id: agent.id }

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.assignee).to eq(agent)
      end

      it 'assigns an agent bot to the conversation' do
        params = { assignee_id: agent_bot.id, assignee_type: 'AgentBot' }

        expect(Conversations::AssignmentService).to receive(:new)
          .with(hash_including(conversation: conversation, assignee_id: agent_bot.id, assignee_type: 'AgentBot'))
          .and_call_original

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['name']).to eq(agent_bot.name)
        conversation.reload
        expect(conversation.assignee_agent_bot).to eq(agent_bot)
        expect(conversation.assignee).to be_nil
      end

      it 'assigns a team to the conversation' do
        team_member = create(:user, account: account, role: :agent, auto_offline: false)
        create(:inbox_member, inbox: conversation.inbox, user: team_member)
        create(:team_member, team: team, user: team_member)
        params = { team_id: team.id }

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.team).to eq(team)
        # assignee will be from team
        expect(conversation.reload.assignee).to eq(team_member)
      end
    end

    context 'when it is an authenticated bot with access to the inbox' do
      let(:agent_bot) { create(:agent_bot, account: account) }
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:team) { create(:team, account: account) }

      before do
        create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)
      end

      it 'assignment of an agent in the conversation by bot agent' do
        create(:inbox_member, user: agent, inbox: conversation.inbox)

        conversation.update!(assignee_id: nil)
        expect(conversation.reload.assignee).to be_nil

        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
             headers: { api_access_token: agent_bot.access_token.token },
             params: {
               assignee_id: agent.id
             },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.assignee).to eq(agent)
      end

      it 'assignment of an team in the conversation by bot agent' do
        create(:inbox_member, user: agent, inbox: conversation.inbox)

        conversation.update!(team_id: nil)
        expect(conversation.reload.team).to be_nil

        post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
             headers: { api_access_token: agent_bot.access_token.token },
             params: {
               team_id: team.id
             },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.team).to eq(team)
      end
    end

    context 'when conversation already has an assignee' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        conversation.update!(assignee: agent)
      end

      it 'unassigns the assignee from the conversation' do
        params = { assignee_id: nil }
        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.assignee).to be_nil
        expect(Conversations::ActivityMessageJob)
          .to(have_been_enqueued.at_least(:once)
        .with(conversation, { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
                              content: "Conversation unassigned by #{agent.name}" }))
      end
    end

    context 'when conversation already has a team' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:team) { create(:team, account: account) }

      before do
        conversation.update!(team: team)
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'unassigns the team from the conversation' do
        params = { team_id: 0 }
        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.team).to be_nil
      end
    end

    # Real production case (IA re-escalation): operator resolved handoff #1
    # without changing team, then the assignee was cleared. When the IA
    # re-escalates and POSTs the SAME team_id, AssignmentHandler's
    # `team_id_changed?` guard silently skips reassignment. The conversation
    # ends up with a team but no assignee. The controller now forces the
    # round-robin explicitly in that case.
    context 'when the request re-sends the team the conversation already has and no assignee is set' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:team) { create(:team, account: account, allow_auto_assign: true) }
      let(:team_member) { create(:user, account: account, role: :agent, auto_offline: false) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
        create(:inbox_member, inbox: conversation.inbox, user: team_member)
        create(:team_member, team: team, user: team_member)
        # Bypass callbacks so the setup doesn't itself run the auto-assign
        # code path we're about to test.
        conversation.update_columns(team_id: team.id, assignee_id: nil) # rubocop:disable Rails/SkipsModelValidations
      end

      it 'runs the round-robin and assigns a team member even though team_id did not change' do
        allow(OnlineStatusTracker).to receive(:get_available_users)
          .and_return({ team_member.id.to_s => 'online' })

        post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
             params: { team_id: team.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.reload.team).to eq(team)
        expect(conversation.reload.assignee).to eq(team_member)
      end

      it 'records an AiAssignmentAttempt row when the caller is IA-driven' do
        allow(OnlineStatusTracker).to receive(:get_available_users)
          .and_return({ team_member.id.to_s => 'online' })
        ia_user = create(:user, account: account, role: :administrator, name: 'IA | Auris')

        expect do
          post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
               params: { team_id: team.id },
               headers: ia_user.create_new_auth_token,
               as: :json
        end.to change(AiAssignmentAttempt, :count).by(1)

        attempt = AiAssignmentAttempt.last
        expect(attempt.team).to eq(team)
        expect(attempt.agent_assigned_id).to eq(team_member.id)
        expect(attempt.online_user_ids).to include(team_member.id)
      end
    end
  end
end
