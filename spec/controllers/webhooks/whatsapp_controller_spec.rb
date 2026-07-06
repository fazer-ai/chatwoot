# rubocop:disable RSpec/AnyInstance
require 'rails_helper'

RSpec.describe 'Webhooks::WhatsappController', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:client_secret) { 'test-whatsapp-secret' }
  let(:body) { { content: 'hello' }.to_json }

  def signature_for(body, secret = client_secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
  end

  def post_whatsapp_webhook(path, body, signature: signature_for(body), env: { WHATSAPP_APP_SECRET: client_secret })
    with_modified_env env do
      post path,
           params: body,
           headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature }
    end
  end

  def post_unsigned_whatsapp_webhook(path, body, env: { WHATSAPP_APP_SECRET: client_secret })
    with_modified_env env do
      post path,
           params: body,
           headers: { 'CONTENT_TYPE' => 'application/json' }
    end
  end

  before do
    InstallationConfig.where(name: 'WHATSAPP_APP_SECRET').delete_all
    GlobalConfig.clear_cache
  end

  describe 'GET /webhooks/verify' do
    it 'returns 401 when valid params are not present' do
      get "/webhooks/whatsapp/#{channel.phone_number}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 when invalid params' do
      get "/webhooks/whatsapp/#{channel.phone_number}",
          params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => 'invalid' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns challenge when valid params' do
      get "/webhooks/whatsapp/#{channel.phone_number}",
          params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => channel.provider_config['webhook_verify_token'] }
      expect(response.body).to include '123456'
    end
  end

  describe 'POST /webhooks/whatsapp/{:phone_number}' do
    # Capture queue-routed enqueues for the WhatsappEventsJob. The controller
    # always reaches the job through `.set(queue: ...).perform_later(...)`,
    # so we stub `set` to return a spy that records which queue it landed in.
    let(:configured_job) { instance_double(ActiveJob::ConfiguredJob, perform_later: true) }
    let(:queues_seen) { [] }

    before do
      # HMAC verify is enforced upstream (4.14). All the routing/behavior
      # tests below predate it and use unsigned POSTs. Stubbing it here
      # keeps every scenario focused on what it's testing; the dedicated
      # signature-validation tests re-enable it via `.and_call_original`.
      allow_any_instance_of(Webhooks::WhatsappController).to receive(:verify_meta_signature!)
      allow(Webhooks::WhatsappEventsJob).to receive(:set) do |opts|
        queues_seen << opts[:queue]
        configured_job
      end
    end

    it 'calls the whatsapp events job with the params for a valid signature' do
      post_whatsapp_webhook('/webhooks/whatsapp/123221321', body)
      expect(configured_job).to have_received(:perform_later)
      expect(response).to have_http_status(:success)
    end

    it 'enqueues the job when awaitResponse is not present' do
      post_whatsapp_webhook('/webhooks/whatsapp/123221321', body)

      expect(configured_job).to have_received(:perform_later)
      expect(response).to have_http_status(:ok)
    end

    it 'routes status / account / presence payloads to :low (default fallback)' do
      post_whatsapp_webhook('/webhooks/whatsapp/123221321', body)

      expect(queues_seen).to eq([:low])
    end

    context 'when the payload is an inbound Baileys message' do
      it 'routes to the :whatsapp_messages queue' do
        post '/webhooks/whatsapp/123221321', params: { event: 'messages.upsert', data: { messages: [] } }

        expect(queues_seen).to eq([:whatsapp_messages])
      end
    end

    context 'when the payload is a non-message Baileys event (presence/status)' do
      it 'routes to :low' do
        post '/webhooks/whatsapp/123221321', params: { event: 'presence.update', data: {} }

        expect(queues_seen).to eq([:low])
      end
    end

    # `connection.update` carries the QR pairing data and the connection
    # state transitions. They are rare per session but operators wait on
    # them interactively — they must not sit behind a backed-up `:low`.
    context 'when the payload is an interactive Baileys event (QR pairing)' do
      it 'routes connection.update to :high' do
        post '/webhooks/whatsapp/123221321', params: { event: 'connection.update', data: { connection: 'connecting' } }

        expect(queues_seen).to eq([:high])
      end

      it 'routes creds.update to :high' do
        post '/webhooks/whatsapp/123221321', params: { event: 'creds.update', data: {} }

        expect(queues_seen).to eq([:high])
      end
    end

    context 'when the payload is an inbound WhatsApp Cloud message' do
      it 'routes "messages" field carrying a messages array to :whatsapp_messages' do
        post '/webhooks/whatsapp/123221321',
             params: {
               object: 'whatsapp_business_account',
               entry: [{ changes: [{ field: 'messages', value: { messages: [{ id: 'wamid.x' }] } }] }]
             }

        expect(queues_seen).to eq([:whatsapp_messages])
      end

      it 'routes "smb_message_echoes" field carrying a message_echoes array to :whatsapp_messages' do
        post '/webhooks/whatsapp/123221321',
             params: {
               object: 'whatsapp_business_account',
               entry: [{ changes: [{ field: 'smb_message_echoes', value: { message_echoes: [{ id: 'wamid.x' }] } }] }]
             }

        expect(queues_seen).to eq([:whatsapp_messages])
      end
    end

    # The Cloud API uses `field: messages` as the envelope for both real
    # inbound messages and status acks (sent / delivered / read). Routing
    # both to :whatsapp_messages drowned real messages behind cosmetic
    # checkmark updates during peak traffic.
    context 'when the payload is a WhatsApp Cloud status ack (sent/delivered/read)' do
      it 'routes "messages" field carrying only a statuses array to :whatsapp_statuses' do
        post '/webhooks/whatsapp/123221321',
             params: {
               object: 'whatsapp_business_account',
               entry: [{
                 changes: [{
                   field: 'messages',
                   value: { statuses: [{ id: 'wamid.x', status: 'delivered' }] }
                 }]
               }]
             }

        expect(queues_seen).to eq([:whatsapp_statuses])
      end
    end

    context 'when the payload is a non-message WhatsApp Cloud event (template/quality/etc.)' do
      it 'routes to :low' do
        post '/webhooks/whatsapp/123221321',
             params: { object: 'whatsapp_business_account', entry: [{ changes: [{ field: 'message_template_status_update', value: {} }] }] }

        expect(queues_seen).to eq([:low])
      end
    end

    context 'when the payload is an inbound Z-API message' do
      it 'routes ReceivedCallback to :whatsapp_messages' do
        post '/webhooks/whatsapp/123221321', params: { type: 'ReceivedCallback' }

        expect(queues_seen).to eq([:whatsapp_messages])
      end
    end

    context 'when the payload is a non-message Z-API event (status/delivery/connection)' do
      it 'routes to :low' do
        post '/webhooks/whatsapp/123221321', params: { type: 'MessageStatusCallback' }

        expect(queues_seen).to eq([:low])
      end
    end

    it 'accepts webhook payloads signed with the channel app secret' do
      allow_any_instance_of(Webhooks::WhatsappController).to receive(:verify_meta_signature!).and_call_original
      channel_secret = 'channel-whatsapp-secret'
      channel.provider_config = channel.provider_config.merge('app_secret' => channel_secret)
      channel.save!

      expect(configured_job).to receive(:perform_later)

      channel_body = {
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              metadata: {
                display_phone_number: channel.phone_number.delete_prefix('+'),
                phone_number_id: channel.provider_config['phone_number_id']
              }
            }
          }]
        }]
      }.to_json

      post_whatsapp_webhook(
        "/webhooks/whatsapp/#{channel.phone_number}",
        channel_body,
        signature: signature_for(channel_body, channel_secret),
        env: {}
      )

      expect(response).to have_http_status(:success)
    end

    it 'skips signature validation for 360dialog channels' do
      allow_any_instance_of(Webhooks::WhatsappController).to receive(:verify_meta_signature!).and_call_original
      dialog_channel = create(:channel_whatsapp, provider: 'default', sync_templates: false, validate_provider_config: false)
      expect(configured_job).to receive(:perform_later)

      post_unsigned_whatsapp_webhook("/webhooks/whatsapp/#{dialog_channel.phone_number}", body)

      expect(response).to have_http_status(:success)
    end

    it 'skips signature validation for manual whatsapp cloud channels without an app secret' do
      allow_any_instance_of(Webhooks::WhatsappController).to receive(:verify_meta_signature!).and_call_original
      channel.update!(
        provider_config: channel.provider_config.except('app_secret', 'app_secret_key', 'api_secret', 'client_secret', 'source')
      )
      expect(configured_job).to receive(:perform_later)

      channel_body = {
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              metadata: {
                display_phone_number: channel.phone_number.delete_prefix('+'),
                phone_number_id: channel.provider_config['phone_number_id']
              }
            }
          }]
        }]
      }.to_json

      post_unsigned_whatsapp_webhook("/webhooks/whatsapp/#{channel.phone_number}", channel_body)

      expect(response).to have_http_status(:success)
    end

    it 'returns unauthorized when signature is missing' do
      allow_any_instance_of(Webhooks::WhatsappController).to receive(:verify_meta_signature!).and_call_original
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      with_modified_env WHATSAPP_APP_SECRET: client_secret do
        post '/webhooks/whatsapp/123221321',
             params: body,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    it 'returns unauthorized when signature is invalid' do
      allow_any_instance_of(Webhooks::WhatsappController).to receive(:verify_meta_signature!).and_call_original
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)

      post_whatsapp_webhook('/webhooks/whatsapp/123221321', body, signature: 'sha256=invalid-signature')

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    context 'when phone number is in inactive list' do
      before do
        allow(GlobalConfig).to receive(:get_value).with('INACTIVE_WHATSAPP_NUMBERS').and_return('+1234567890,+9876543210')
      end

      it 'returns service unavailable for inactive phone number in URL params' do
        allow(Rails.logger).to receive(:warn)

        post_whatsapp_webhook('/webhooks/whatsapp/+1234567890', body)

        expect(Rails.logger).to have_received(:warn).with('Rejected webhook for inactive WhatsApp number: +1234567890')
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Inactive WhatsApp number')
      end
    end

    context 'when INACTIVE_WHATSAPP_NUMBERS config is not set' do
      before do
        allow(GlobalConfig).to receive(:get_value).with('INACTIVE_WHATSAPP_NUMBERS').and_return(nil)
      end

      it 'processes the webhook normally' do
        post_whatsapp_webhook('/webhooks/whatsapp/+1234567890', body)

        expect(configured_job).to have_received(:perform_later)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when importMode is true (Baileys history backfill)' do
      it 'routes the job to the dedicated :whatsapp_history queue' do
        post '/webhooks/whatsapp/123221321', params: { content: 'hello', importMode: true }

        expect(queues_seen).to eq([:whatsapp_history])
      end

      it 'wins over the live-message routing even when the payload looks like a real message' do
        post '/webhooks/whatsapp/123221321', params: { event: 'messages.upsert', data: {}, importMode: true }

        expect(queues_seen).to eq([:whatsapp_history])
      end
    end

    context 'when awaitResponse param is present' do
      # baileys channels skip signature verification (meta_signature_verification_required? short-circuits
      # for non whatsapp_cloud providers), so an unsigned POST is valid here.
      let(:baileys_channel) { create(:channel_whatsapp, provider: 'baileys', sync_templates: false, validate_provider_config: false) }

      it 'calls the whatsapp events job synchronously' do
        allow(Webhooks::WhatsappEventsJob).to receive(:perform_now)

        post "/webhooks/whatsapp/#{baileys_channel.phone_number}", params: { content: 'hello', awaitResponse: true }

        expect(Webhooks::WhatsappEventsJob).to have_received(:perform_now)
        expect(response).to have_http_status(:ok)
      end

      it 'returns 401 when InvalidWebhookVerifyToken is raised' do
        allow(Webhooks::WhatsappEventsJob).to receive(:perform_now).and_raise(Whatsapp::IncomingMessageBaileysService::InvalidWebhookVerifyToken)

        post "/webhooks/whatsapp/#{baileys_channel.phone_number}", params: { content: 'hello', awaitResponse: true }

        expect(response).to have_http_status(:unauthorized)
      end

      context 'when MessageNotFoundError is raised (race with SendReplyJob)' do
        before do
          allow(Webhooks::WhatsappEventsJob).to receive(:perform_now)
            .and_raise(Whatsapp::BaileysHandlers::MessagesUpdate::MessageNotFoundError)
        end

        it 'responds 200 so Baileys stops retrying the webhook' do
          post "/webhooks/whatsapp/#{baileys_channel.phone_number}", params: { content: 'hello', awaitResponse: true }

          expect(response).to have_http_status(:ok)
        end

        it 're-enqueues the job with a delay to give SendReplyJob time to persist source_id' do
          post '/webhooks/whatsapp/123221321', params: { content: 'hello', awaitResponse: true }

          expect(Webhooks::WhatsappEventsJob).to have_received(:set).with(wait: Webhooks::WhatsappController::MESSAGE_NOT_FOUND_RETRY_DELAY)
          expect(configured_job).to have_received(:perform_later)
        end

        it 'logs a warning so the race can be tracked via log search' do
          allow(Rails.logger).to receive(:warn)

          post '/webhooks/whatsapp/123221321', params: { event: 'messages.update', awaitResponse: true }

          expect(Rails.logger).to have_received(:warn).with(/MessageNotFoundError, re-enqueueing/)
        end
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance
