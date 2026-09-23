require 'rails_helper'

RSpec.describe 'Assignable Agents API', type: :request do
  let(:account) { create(:account) }
  let(:agent1) { create(:user, account: account, role: :agent) }
  let!(:agent2) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/{account.id}/assignable_agents' do
    let(:inbox1) { create(:inbox, account: account) }
    let(:inbox2) { create(:inbox, account: account) }

    before do
      create(:inbox_member, user: agent1, inbox: inbox1)
      create(:inbox_member, user: agent1, inbox: inbox2)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/assignable_agents"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is not part of an inbox' do
      context 'when the user is an admininstrator' do
        it 'returns all assignable inbox members along with administrators' do
          get "/api/v1/accounts/#{account.id}/assignable_agents",
              params: { inbox_ids: [inbox1.id, inbox2.id] },
              headers: admin.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
          expect(response_data.size).to eq(2)
          expect(response_data.pluck(:role)).to include('agent', 'administrator')
        end
      end

      context 'when the user is an agent' do
        it 'returns unauthorized' do
          get "/api/v1/accounts/#{account.id}/assignable_agents",
              params: { inbox_ids: [inbox1.id, inbox2.id] },
              headers: agent2.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'when the user is part of the inbox' do
      it 'returns all assignable inbox members along with administrators' do
        get "/api/v1/accounts/#{account.id}/assignable_agents",
            params: { inbox_ids: [inbox1.id, inbox2.id] },
            headers: agent1.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = JSON.parse(response.body, symbolize_names: true)[:payload]
        expect(response_data.size).to eq(2)
        expect(response_data.pluck(:role)).to include('agent', 'administrator')
      end

      # Only the bot serving the requested inboxes is offered (#721): a bot of another inbox, or one
      # serving none, would own the conversation without ever answering it.
      context 'with Agent Bots' do
        let!(:inbox_bot) { create(:agent_bot, account: account, name: 'Inbox bot') }
        let!(:other_inbox_bot) { create(:agent_bot, account: account, name: 'Other inbox bot') }
        let!(:account_bot) { create(:agent_bot, account: account, name: 'Account bot') }
        let!(:global_bot) { create(:agent_bot, account: nil, name: 'Global bot') }
        let(:inbox3) { create(:inbox, account: account) }

        before do
          create(:inbox_member, user: agent1, inbox: inbox3)
          create(:agent_bot_inbox, inbox: inbox1, agent_bot: inbox_bot)
          create(:agent_bot_inbox, inbox: inbox3, agent_bot: other_inbox_bot)
          create(:agent_bot_observer, inbox: inbox1, agent_bot: account_bot)
        end

        def assignable_bots(inbox_ids)
          get "/api/v1/accounts/#{account.id}/assignable_agents",
              params: { inbox_ids: inbox_ids, include_ai_assignees: true },
              headers: agent1.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          response.parsed_body['payload'].select { |owner| owner['assignee_type'] == 'AgentBot' }.pluck('name')
        end

        it 'returns the users with the AI assignees flag' do
          get "/api/v1/accounts/#{account.id}/assignable_agents",
              params: { inbox_ids: [inbox1.id], include_ai_assignees: true },
              headers: agent1.create_new_auth_token,
              as: :json

          response_data = response.parsed_body['payload']
          expect(response_data.pluck('assignee_type')).to include('User', 'AgentBot')
          expect(response_data.pluck('name')).to include(agent1.name, admin.name)
        end

        it 'offers only the bot serving the inbox' do
          bots = assignable_bots([inbox1.id])

          expect(bots).to eq([inbox_bot.name])
          expect(bots).not_to include(other_inbox_bot.name, account_bot.name, global_bot.name)
        end

        it 'offers no bot for an inbox without one' do
          expect(assignable_bots([inbox2.id])).to be_empty
        end

        it 'offers the bot serving every requested inbox' do
          create(:agent_bot_inbox, inbox: inbox2, agent_bot: inbox_bot)

          expect(assignable_bots([inbox1.id, inbox2.id])).to eq([inbox_bot.name])
        end

        it 'offers no bot when the requested inboxes are served by different bots' do
          expect(assignable_bots([inbox1.id, inbox3.id])).to be_empty
        end

        it 'offers no bot when only some of the requested inboxes have one' do
          expect(assignable_bots([inbox1.id, inbox2.id])).to be_empty
        end

        it 'does not offer the inbox bot while its connection is inactive' do
          inbox1.agent_bot_inbox.update!(status: :inactive)

          expect(assignable_bots([inbox1.id])).to be_empty
        end
      end
    end
  end
end
