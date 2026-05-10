require 'rails_helper'

RSpec.describe 'FunnelStage API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:funnel_stage) { create(:funnel_stage, name: 'Novo lead', position: 1) }

  describe 'GET /api/v1/accounts/:account_id/funnel_stages' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/funnel_stages"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the list of stages for an admin' do
        get "/api/v1/accounts/#{account.id}/funnel_stages",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(funnel_stage.name)
      end

      it 'returns the list of stages for an agent' do
        get "/api/v1/accounts/#{account.id}/funnel_stages",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/funnel_stages/:id' do
    context 'when authenticated' do
      it 'returns the stage' do
        get "/api/v1/accounts/#{account.id}/funnel_stages/#{funnel_stage.id}",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(funnel_stage.name)
      end
    end
  end

  describe 'write endpoints are not exposed at the account scope' do
    # Funnel stages are global Auris records — only Super Admin can mutate them.
    it 'POST returns 404 / routing error' do
      expect do
        post "/api/v1/accounts/#{account.id}/funnel_stages",
             headers: admin.create_new_auth_token,
             params: { funnel_stage: { name: 'New stage', position: 99, color: '#000000' } },
             as: :json
      end.not_to change(FunnelStage, :count)

      expect(response.status).to be_in([404, 405])
    end

    it 'PATCH returns 404 / routing error' do
      patch "/api/v1/accounts/#{account.id}/funnel_stages/#{funnel_stage.id}",
            headers: admin.create_new_auth_token,
            params: { funnel_stage: { name: 'Hacked' } },
            as: :json

      expect(response.status).to be_in([404, 405])
      expect(funnel_stage.reload.name).to eq('Novo lead')
    end

    it 'DELETE returns 404 / routing error' do
      delete "/api/v1/accounts/#{account.id}/funnel_stages/#{funnel_stage.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response.status).to be_in([404, 405])
      expect(FunnelStage.find_by(id: funnel_stage.id)).to be_present
    end
  end
end
