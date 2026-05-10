require 'rails_helper'

RSpec.describe 'Super Admin funnel-stages dashboard', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:funnel_stage) { create(:funnel_stage, name: 'Novo lead', position: 1) }

  describe 'GET /super_admin/funnel_stages' do
    context 'when unauthenticated' do
      it 'redirects to login' do
        get '/super_admin/funnel_stages'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when authenticated' do
      it 'lists the stages' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/funnel_stages'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(funnel_stage.name)
      end
    end
  end

  describe 'POST /super_admin/funnel_stages' do
    let(:params) do
      {
        funnel_stage: {
          name: 'Qualificação',
          color: '#0ea5e9',
          position: 50,
          active: true,
          closed: false
        }
      }
    end

    it 'creates a stage when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      expect { post '/super_admin/funnel_stages', params: params }.to change(FunnelStage, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'PATCH /super_admin/funnel_stages/:id' do
    it 'updates a stage when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      patch "/super_admin/funnel_stages/#{funnel_stage.id}", params: { funnel_stage: { name: 'Renomeado' } }
      expect(response).to have_http_status(:redirect)
      expect(funnel_stage.reload.name).to eq('Renomeado')
    end
  end

  describe 'DELETE /super_admin/funnel_stages/:id' do
    it 'destroys the stage when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      delete "/super_admin/funnel_stages/#{funnel_stage.id}"
      expect(response).to have_http_status(:redirect)
      expect(FunnelStage.find_by(id: funnel_stage.id)).to be_nil
    end
  end
end
