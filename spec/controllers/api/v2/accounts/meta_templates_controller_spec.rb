require 'rails_helper'

RSpec.describe 'Meta Templates API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:cloud_channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           validate_provider_config: false,
           sync_templates: false)
  end
  let(:cloud_inbox) { cloud_channel.inbox }
  let(:baileys_channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'baileys',
           validate_provider_config: false,
           sync_templates: false)
  end
  let(:baileys_inbox) { baileys_channel.inbox }

  let(:sample_templates) do
    [
      {
        'id' => '123',
        'name' => 'confirmacao_agenda',
        'status' => 'APPROVED',
        'category' => 'UTILITY',
        'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}' }]
      }
    ]
  end

  before do
    cloud_channel.update!(message_templates: sample_templates, message_templates_last_updated: Time.current)
  end

  describe 'GET /api/v2/accounts/{account_id}/meta_templates' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/meta_templates", params: { inbox_id: cloud_inbox.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the cached templates for the given cloud inbox' do
        get "/api/v2/accounts/#{account.id}/meta_templates",
            params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['inbox']['id']).to eq(cloud_inbox.id)
        expect(body['templates'].size).to eq(1)
        expect(body['templates'].first['name']).to eq('confirmacao_agenda')
        expect(body['last_synced_at']).to be_present
      end

      it 'is available to agents (sidebar hides it on Baileys-only accounts already)' do
        get "/api/v2/accounts/#{account.id}/meta_templates",
            params: { inbox_id: cloud_inbox.id }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['templates'].size).to eq(1)
      end

      it 'returns 422 when the inbox is not a Cloud WhatsApp inbox' do
        get "/api/v2/accounts/#{account.id}/meta_templates",
            params: { inbox_id: baileys_inbox.id }, headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
      end

      it 'returns 404 when the inbox belongs to a different account' do
        other_account = create(:account)
        other_channel = create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud',
                                                  validate_provider_config: false, sync_templates: false)

        get "/api/v2/accounts/#{account.id}/meta_templates",
            params: { inbox_id: other_channel.inbox.id }, headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v2/accounts/{account_id}/meta_templates/sync' do
    let(:refreshed) do
      [
        {
          'id' => '456',
          'name' => 'confirmacao_agenda',
          'status' => 'PENDING',
          'category' => 'UTILITY',
          'language' => 'pt_BR',
          'components' => [{ 'type' => 'BODY', 'text' => 'Nova versão em análise' }]
        }
      ]
    end

    it 'triggers an inline sync and returns the fresh templates' do
      # rubocop:disable RSpec/AnyInstance — controller loads the channel via
      # `Current.account.inboxes.find(...).channel`, so intercepting a specific
      # instance would require re-plumbing the controller with a boundary that
      # doesn't exist yet. The stub is scoped to this example.
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates) do
        cloud_channel.update!(message_templates: refreshed, message_templates_last_updated: Time.current)
      end
      # rubocop:enable RSpec/AnyInstance

      post "/api/v2/accounts/#{account.id}/meta_templates/sync",
           params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['templates'].first['status']).to eq('PENDING')
    end

    it 'returns 422 with a friendly error when Meta refresh raises' do
      allow_any_instance_of(Channel::Whatsapp).to receive(:sync_templates).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance

      post "/api/v2/accounts/#{account.id}/meta_templates/sync",
           params: { inbox_id: cloud_inbox.id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
    end
  end
end
