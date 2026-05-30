require 'rails_helper'

RSpec.describe 'Super Admin inbox status report', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:connected_baileys) do
    create(:channel_whatsapp, account: account, phone_number: '+5585999990020', provider: 'baileys',
                              provider_connection: { 'connection' => 'open' },
                              validate_provider_config: false, sync_templates: false)
  end

  describe 'GET /super_admin/reports/inbox_status' do
    it 'redirects unauthenticated requests' do
      get '/super_admin/reports/inbox_status'
      expect(response).to have_http_status(:redirect)
    end

    it 'renders the page when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/inbox_status'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('InboxStatusIndex')
    end
  end

  describe 'GET /super_admin/reports/inbox_status/data' do
    let!(:disconnected_baileys) do
      create(:channel_whatsapp, account: create(:account), phone_number: '+5585999990021', provider: 'baileys',
                                provider_connection: { 'connection' => 'close' },
                                validate_provider_config: false, sync_templates: false)
    end
    let!(:connected_zapi) do
      create(:channel_whatsapp, account: create(:account), phone_number: '+5585999990023', provider: 'zapi',
                                provider_connection: { 'connection' => 'open' },
                                validate_provider_config: false, sync_templates: false)
    end
    let!(:disconnected_zapi) do
      create(:channel_whatsapp, account: create(:account), phone_number: '+5585999990024', provider: 'zapi',
                                provider_connection: { 'connection' => 'close' },
                                validate_provider_config: false, sync_templates: false)
    end
    let!(:cloud_inbox) do
      create(:channel_whatsapp, account: account, phone_number: '+5585999990022', provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false)
    end

    it 'redirects unauthenticated requests' do
      get '/super_admin/reports/inbox_status/data'
      expect(response).to have_http_status(:redirect)
    end

    it 'returns every WhatsApp inbox across providers' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/inbox_status/data'

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['inboxes'].length).to eq(5)
      phones = body['inboxes'].pluck('phone_number')
      expect(phones).to contain_exactly(
        connected_baileys.phone_number,
        disconnected_baileys.phone_number,
        connected_zapi.phone_number,
        disconnected_zapi.phone_number,
        cloud_inbox.phone_number
      )
    end

    it 'reports Baileys + Z-API as connected based on provider_connection state' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/inbox_status/data'

      body = response.parsed_body
      by_phone = body['inboxes'].index_by { |row| row['phone_number'] }

      expect(by_phone[connected_baileys.phone_number]).to include('connected' => true, 'provider' => 'baileys', 'reconnect_supported' => true)
      expect(by_phone[disconnected_baileys.phone_number]).to include('connected' => false, 'provider' => 'baileys', 'reconnect_supported' => true)
      expect(by_phone[connected_zapi.phone_number]).to include('connected' => true, 'provider' => 'zapi', 'reconnect_supported' => true)
      expect(by_phone[disconnected_zapi.phone_number]).to include('connected' => false, 'provider' => 'zapi', 'reconnect_supported' => true)
    end

    it 'always reports WhatsApp Cloud inboxes as connected and not reconnectable' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/inbox_status/data'

      body = response.parsed_body
      cloud_row = body['inboxes'].find { |row| row['phone_number'] == cloud_inbox.phone_number }
      expect(cloud_row).to include(
        'provider' => 'whatsapp_cloud',
        'connected' => true,
        'connection' => 'open',
        'reconnect_supported' => false
      )
    end

    it 'tallies connected vs disconnected across all providers' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/inbox_status/data'

      body = response.parsed_body
      # 3 connected: baileys-open, zapi-open, cloud-always; 2 disconnected: baileys-close, zapi-close
      expect(body['counts']).to eq('connected' => 3, 'disconnected' => 2)
    end

    describe 'outgoing 24h failure stats' do
      let(:inbox) { connected_baileys.inbox }
      let(:conversation) { create(:conversation, inbox: inbox, account: account) }

      it 'counts outgoing messages and ones missing a source_id in the last 24h' do
        # 3 ok, 2 failed (no source_id), 1 ignored (older than window)
        3.times { create(:message, conversation: conversation, message_type: :outgoing, source_id: SecureRandom.hex) }
        2.times { create(:message, conversation: conversation, message_type: :outgoing, source_id: nil) }
        old = create(:message, conversation: conversation, message_type: :outgoing, source_id: nil)
        old.update_columns(created_at: 25.hours.ago) # rubocop:disable Rails/SkipsModelValidations

        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/reports/inbox_status/data'

        row = response.parsed_body['inboxes'].find { |r| r['phone_number'] == connected_baileys.phone_number }
        expect(row).to include('outgoing_24h_total' => 5, 'outgoing_24h_failed' => 2)
      end

      it 'reports zero counts for inboxes with no recent outgoing traffic' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/reports/inbox_status/data'

        rows = response.parsed_body['inboxes']
        expect(rows).to all(include('outgoing_24h_total' => 0, 'outgoing_24h_failed' => 0))
      end

      it 'ignores incoming messages and messages from other inboxes' do
        # Incoming on the same inbox — must NOT count
        create(:message, conversation: conversation, message_type: :incoming, source_id: nil)
        # Outgoing on a different inbox — must NOT bleed into this inbox's stats
        other_conv = create(:conversation, inbox: cloud_inbox.inbox, account: cloud_inbox.inbox.account)
        create(:message, conversation: other_conv, message_type: :outgoing, source_id: nil)

        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/reports/inbox_status/data'

        body = response.parsed_body
        baileys_row = body['inboxes'].find { |r| r['phone_number'] == connected_baileys.phone_number }
        cloud_row = body['inboxes'].find { |r| r['phone_number'] == cloud_inbox.phone_number }
        expect(baileys_row).to include('outgoing_24h_total' => 0, 'outgoing_24h_failed' => 0)
        expect(cloud_row).to include('outgoing_24h_total' => 1, 'outgoing_24h_failed' => 1)
      end
    end
  end
end
