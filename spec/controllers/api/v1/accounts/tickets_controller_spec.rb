require 'rails_helper'

RSpec.describe 'Tickets API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }

  describe 'GET /api/v1/accounts/{account.id}/tickets' do
    it 'returns 401 for unauthenticated requests' do
      get "/api/v1/accounts/#{account.id}/tickets"
      expect(response).to have_http_status(:unauthorized)
    end

    context 'when authenticated' do
      let!(:agent_ticket) { create(:ticket, account: account, user: agent) }
      let!(:another_agent) { create(:user, account: account, role: :agent) }
      let!(:other_ticket) { create(:ticket, account: account, user: another_agent) }

      it 'narrows the payload to the agent own tickets' do
        get "/api/v1/accounts/#{account.id}/tickets",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to eq([agent_ticket.id])
      end

      it 'returns every ticket in the account for administrators' do
        get "/api/v1/accounts/#{account.id}/tickets",
            headers: manager.create_new_auth_token,
            as: :json

        ids = response.parsed_body['payload'].pluck('id').sort
        expect(ids).to eq([agent_ticket.id, other_ticket.id].sort)
      end

      it 'filters by ClickUp status name so Meus Tickets can offer a quick tab' do
        agent_ticket.update!(clickup_status_name: 'em análise')

        get "/api/v1/accounts/#{account.id}/tickets",
            params: { status: 'em análise' },
            headers: manager.create_new_auth_token,
            as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to eq([agent_ticket.id])
      end

      # The "Ocultar finalizadas" checkbox on Meus Tickets flips this param.
      # Encerrado tickets drop out — everything else (Aberto, Em análise, or
      # unsynced) stays. Explicit status filter continues to override.
      it 'hides encerrado tickets when hide_finished=true' do
        agent_ticket.update!(clickup_status_name: 'aberto')
        other_ticket.update!(clickup_status_name: 'encerrado')

        get "/api/v1/accounts/#{account.id}/tickets",
            params: { hide_finished: 'true' },
            headers: manager.create_new_auth_token,
            as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to eq([agent_ticket.id])
      end

      it 'ignores hide_finished when the value is not truthy (e.g. blank param)' do
        agent_ticket.update!(clickup_status_name: 'encerrado')

        get "/api/v1/accounts/#{account.id}/tickets",
            params: { hide_finished: 'false' },
            headers: manager.create_new_auth_token,
            as: :json

        ids = response.parsed_body['payload'].pluck('id').sort
        expect(ids).to eq([agent_ticket.id, other_ticket.id].sort)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/tickets' do
    it 'rejects unauthenticated callers' do
      post "/api/v1/accounts/#{account.id}/tickets", params: { message_id: message.id, relatar_problema: 'x' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates a ticket and returns the freshly built payload' do
      post "/api/v1/accounts/#{account.id}/tickets",
           params: { message_id: message.id, relatar_problema: 'IA respondeu em espanhol', comportamento_esperado: 'Deveria ser em português' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['relatar_problema']).to eq('IA respondeu em espanhol')
      expect(body['comportamento_esperado']).to eq('Deveria ser em português')
      expect(body['user']['id']).to eq(agent.id)
      expect(Ticket.last.context).to eq(message)
    end

    it 'enqueues the ClickUp sync job for the freshly built ticket' do
      expect do
        post "/api/v1/accounts/#{account.id}/tickets",
             params: { message_id: message.id, relatar_problema: 'x', comportamento_esperado: 'y' },
             headers: agent.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(Integrations::Clickup::CreateTaskJob)
    end

    # comportamento_esperado turned into a required field so ops always has
    # the two sides of the story (what happened, what should have happened).
    # Ship a proper 422 with the message so the frontend can surface it.
    it 'returns 422 when comportamento_esperado is missing' do
      post "/api/v1/accounts/#{account.id}/tickets",
           params: { message_id: message.id, relatar_problema: 'IA respondeu em espanhol' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/comportamento/i)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/tickets/:id/add_comment' do
    let(:ticket) do
      create(:ticket, account: account, user: agent, sync_status: :synced, clickup_task_id: 'CU_1')
    end

    it 'queues the comment for the ClickUp side' do
      expect do
        post "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}/add_comment",
             params: { comment: 'mais uma info' },
             headers: agent.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(Integrations::Clickup::AddCommentJob).with(ticket.id, 'mais uma info', agent.id)

      expect(response).to have_http_status(:accepted)
    end

    it 'refuses to comment on a ticket that has not synced yet — nothing to attach it to' do
      pending_ticket = create(:ticket, account: account, user: agent, sync_status: :pending_sync)

      post "/api/v1/accounts/#{account.id}/tickets/#{pending_ticket.id}/add_comment",
           params: { comment: 'oi' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects blank comments' do
      post "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}/add_comment",
           params: { comment: '' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'forbids an agent commenting on another agent ticket' do
      other_agent = create(:user, account: account, role: :agent)
      other_ticket = create(:ticket, account: account, user: other_agent, sync_status: :synced, clickup_task_id: 'CU_2')

      post "/api/v1/accounts/#{account.id}/tickets/#{other_ticket.id}/add_comment",
           params: { comment: 'oi' },
           headers: agent.create_new_auth_token,
           as: :json

      # Pundit responds 401 by default for unauthorized actions in this app's setup.
      expect(response.status).to be_in([401, 403, 404])
    end
  end
end
