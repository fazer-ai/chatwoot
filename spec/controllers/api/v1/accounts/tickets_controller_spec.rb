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

      # Manager is a separate role from administrator (agent=0, administrator=1,
      # manager=2 on account_users). Both need the same "see every ticket in
      # the account" behavior — Meus Tickets is the operations dashboard for
      # both roles.
      it 'returns every ticket in the account for managers' do
        team_manager = create(:user, account: account, role: :manager)

        get "/api/v1/accounts/#{account.id}/tickets",
            headers: team_manager.create_new_auth_token,
            as: :json

        ids = response.parsed_body['payload'].pluck('id').sort
        expect(ids).to eq([agent_ticket.id, other_ticket.id].sort)
      end

      # Cross-account isolation: an admin/manager on account A must never see
      # tickets from account B. Guarded by `scope.where(account_id: account.id)`
      # in TicketPolicy::Scope, but any regression here leaks tickets between
      # tenants so keep it locked with an explicit spec.
      it 'never leaks tickets from other accounts to admins on this account' do
        other_account = create(:account)
        other_account_agent = create(:user, account: other_account, role: :agent)
        _foreign_ticket = create(:ticket, account: other_account, user: other_account_agent)

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

  describe 'GET /api/v1/accounts/{account.id}/tickets/:id' do
    let(:other_agent) { create(:user, account: account, role: :agent) }
    let(:their_ticket) { create(:ticket, account: account, user: other_agent) }

    it 'lets a manager open another agent ticket detail modal' do
      team_manager = create(:user, account: account, role: :manager)

      get "/api/v1/accounts/#{account.id}/tickets/#{their_ticket.id}",
          headers: team_manager.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(their_ticket.id)
    end

    it 'refuses to show a cross-account ticket to a manager on this account' do
      other_account = create(:account)
      other_account_agent = create(:user, account: other_account, role: :agent)
      foreign_ticket = create(:ticket, account: other_account, user: other_account_agent)
      team_manager = create(:user, account: account, role: :manager)

      get "/api/v1/accounts/#{account.id}/tickets/#{foreign_ticket.id}",
          headers: team_manager.create_new_auth_token,
          as: :json

      expect(response.status).to be_in([401, 403, 404])
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

    # Manager can add comments to any ticket in the account — Meus Tickets
    # dashboard is theirs to work with.
    it 'lets a manager comment on another agent ticket in the same account' do
      other_agent = create(:user, account: account, role: :agent)
      other_ticket = create(:ticket, account: account, user: other_agent, sync_status: :synced, clickup_task_id: 'CU_3')
      team_manager = create(:user, account: account, role: :manager)

      expect do
        post "/api/v1/accounts/#{account.id}/tickets/#{other_ticket.id}/add_comment",
             params: { comment: 'follow-up do manager' },
             headers: team_manager.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(Integrations::Clickup::AddCommentJob).with(other_ticket.id, 'follow-up do manager', team_manager.id)

      expect(response).to have_http_status(:accepted)
    end

    # A manager on account A must not be able to comment on account B tickets.
    it 'forbids a manager from commenting on a ticket that belongs to another account' do
      other_account = create(:account)
      other_account_agent = create(:user, account: other_account, role: :agent)
      foreign_ticket = create(:ticket, account: other_account, user: other_account_agent, sync_status: :synced, clickup_task_id: 'CU_4')
      team_manager = create(:user, account: account, role: :manager)

      post "/api/v1/accounts/#{account.id}/tickets/#{foreign_ticket.id}/add_comment",
           params: { comment: 'oi' },
           headers: team_manager.create_new_auth_token,
           as: :json

      # Ticket lookup already narrows to `Current.account.tickets`, so a
      # cross-account id is a plain 404 (does not exist "for us").
      expect(response.status).to be_in([401, 403, 404])
    end
  end
end
