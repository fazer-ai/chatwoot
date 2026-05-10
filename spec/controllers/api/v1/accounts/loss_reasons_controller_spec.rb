require 'rails_helper'

RSpec.describe 'LossReason API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:loss_reason) { create(:loss_reason, name: 'Sem orçamento', position: 1) }

  describe 'GET /api/v1/accounts/:account_id/loss_reasons' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/loss_reasons"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the list of reasons for an admin' do
        get "/api/v1/accounts/#{account.id}/loss_reasons",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(loss_reason.name)
      end

      it 'returns the list of reasons for an agent' do
        get "/api/v1/accounts/#{account.id}/loss_reasons",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/loss_reasons/:id' do
    context 'when authenticated' do
      it 'returns the reason' do
        get "/api/v1/accounts/#{account.id}/loss_reasons/#{loss_reason.id}",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(loss_reason.name)
      end
    end
  end

  describe 'write endpoints are not exposed at the account scope' do
    # Loss reasons are global Auris records — only Super Admin can mutate them.
    it 'POST returns 404 / routing error' do
      expect do
        post "/api/v1/accounts/#{account.id}/loss_reasons",
             headers: admin.create_new_auth_token,
             params: { loss_reason: { name: 'New reason', position: 99 } },
             as: :json
      end.not_to change(LossReason, :count)

      expect(response.status).to be_in([404, 405])
    end

    it 'PATCH returns 404 / routing error' do
      patch "/api/v1/accounts/#{account.id}/loss_reasons/#{loss_reason.id}",
            headers: admin.create_new_auth_token,
            params: { loss_reason: { name: 'Hacked' } },
            as: :json

      expect(response.status).to be_in([404, 405])
      expect(loss_reason.reload.name).to eq('Sem orçamento')
    end

    it 'DELETE returns 404 / routing error' do
      delete "/api/v1/accounts/#{account.id}/loss_reasons/#{loss_reason.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response.status).to be_in([404, 405])
      expect(LossReason.find_by(id: loss_reason.id)).to be_present
    end
  end
end
