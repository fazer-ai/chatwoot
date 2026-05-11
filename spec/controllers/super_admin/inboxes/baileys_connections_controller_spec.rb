require 'rails_helper'

RSpec.describe 'Super Admin Baileys connections', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:baileys_channel) do
    create(:channel_whatsapp, account: account, phone_number: '+5585999990010', provider: 'baileys',
                              provider_connection: { 'connection' => 'connecting', 'qr_data_url' => 'data:image/png;base64,xyz' },
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { baileys_channel.inbox }
  let!(:cloud_channel) do
    create(:channel_whatsapp, account: account, phone_number: '+5585999990011', provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end

  describe 'GET /super_admin/inboxes/:inbox_id/baileys_connection' do
    it 'redirects unauthenticated requests' do
      get "/super_admin/inboxes/#{inbox.id}/baileys_connection"
      expect(response).to have_http_status(:redirect)
    end

    it 'returns the full provider_connection state including qr_data_url' do
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/inboxes/#{inbox.id}/baileys_connection"
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['connection']).to eq('connecting')
      expect(body['qr_data_url']).to eq('data:image/png;base64,xyz')
    end

    it '404s for inboxes that are not Baileys' do
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/inboxes/#{cloud_channel.inbox.id}/baileys_connection"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /super_admin/inboxes/:inbox_id/baileys_connection' do
    it 'invokes setup_channel_provider on the channel' do
      sign_in(super_admin, scope: :super_admin)
      stub_request(:any, /baileys\.api/).to_return(status: 200, body: '{}')

      post "/super_admin/inboxes/#{inbox.id}/baileys_connection"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('connection' => 'connecting')
    end
  end

  describe 'DELETE /super_admin/inboxes/:inbox_id/baileys_connection' do
    it 'disconnects and forces connection state to close' do
      sign_in(super_admin, scope: :super_admin)
      stub_request(:any, /baileys\.api/).to_return(status: 200, body: '{}')

      delete "/super_admin/inboxes/#{inbox.id}/baileys_connection"

      expect(response).to have_http_status(:success)
      expect(baileys_channel.reload.provider_connection['connection']).to eq('close')
    end
  end
end
