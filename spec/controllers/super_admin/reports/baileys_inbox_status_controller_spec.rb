require 'rails_helper'

RSpec.describe 'Super Admin Baileys inbox status report', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:connected_baileys) do
    create(:channel_whatsapp, account: account, phone_number: '+5585999990020', provider: 'baileys',
                              provider_connection: { 'connection' => 'open' },
                              validate_provider_config: false, sync_templates: false)
  end

  describe 'GET /super_admin/reports/baileys_inbox_status' do
    it 'redirects unauthenticated requests' do
      get '/super_admin/reports/baileys_inbox_status'
      expect(response).to have_http_status(:redirect)
    end

    it 'renders the page when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/baileys_inbox_status'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('BaileysInboxStatusIndex')
    end
  end

  describe 'GET /super_admin/reports/baileys_inbox_status/data' do
    let!(:disconnected_baileys) do
      create(:channel_whatsapp, account: create(:account), phone_number: '+5585999990021', provider: 'baileys',
                                provider_connection: { 'connection' => 'close' },
                                validate_provider_config: false, sync_templates: false)
    end

    before do
      create(:channel_whatsapp, account: account, phone_number: '+5585999990022', provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false)
    end

    it 'redirects unauthenticated requests' do
      get '/super_admin/reports/baileys_inbox_status/data'
      expect(response).to have_http_status(:redirect)
    end

    it 'returns only Baileys inboxes with their connection state and aggregate counts' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/baileys_inbox_status/data'

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['inboxes'].length).to eq(2)
      phones = body['inboxes'].pluck('phone_number')
      expect(phones).to contain_exactly(connected_baileys.phone_number, disconnected_baileys.phone_number)
      expect(body['counts']).to eq('connected' => 1, 'disconnected' => 1)
    end
  end
end
