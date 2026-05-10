require 'rails_helper'

RSpec.describe 'Super Admin loss-reasons dashboard', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:loss_reason) { create(:loss_reason, name: 'Sem orçamento', position: 1) }

  describe 'GET /super_admin/loss_reasons' do
    context 'when unauthenticated' do
      it 'redirects to login' do
        get '/super_admin/loss_reasons'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when authenticated' do
      it 'lists the reasons' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/loss_reasons'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(loss_reason.name)
      end
    end
  end

  describe 'POST /super_admin/loss_reasons' do
    let(:params) { { loss_reason: { name: 'Concorrente', position: 10, active: true } } }

    it 'creates a reason when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      expect { post '/super_admin/loss_reasons', params: params }.to change(LossReason, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'PATCH /super_admin/loss_reasons/:id' do
    it 'updates a reason when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      patch "/super_admin/loss_reasons/#{loss_reason.id}", params: { loss_reason: { name: 'Renomeado' } }
      expect(response).to have_http_status(:redirect)
      expect(loss_reason.reload.name).to eq('Renomeado')
    end
  end

  describe 'DELETE /super_admin/loss_reasons/:id' do
    it 'destroys the reason when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      delete "/super_admin/loss_reasons/#{loss_reason.id}"
      expect(response).to have_http_status(:redirect)
      expect(LossReason.find_by(id: loss_reason.id)).to be_nil
    end
  end
end
