require 'rails_helper'

RSpec.describe 'Webhooks::Whatsapp::ZapiController', type: :request do
  let(:channel) do
    create(:channel_whatsapp, provider: 'zapi', sync_templates: false, validate_provider_config: false).tap do |zapi|
      zapi.provider_config = zapi.provider_config.merge('webhook_verify_token' => 'zapi-token')
      zapi.save!(validate: false)
    end
  end

  before { allow(Webhooks::WhatsappEventsJob).to receive(:perform_later) }

  it 'queues the event for the inbox, without the token' do
    post "/webhooks/whatsapp/zapi/#{channel.id}/zapi-token", params: { type: 'ReceivedCallback', phone: '5511999999999' }, as: :json

    expect(response).to have_http_status(:ok)
    expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later) do |args|
      expect(args).to include('phone_number' => channel.phone_number, 'type' => 'ReceivedCallback', 'phone' => '5511999999999')
      expect(args.keys).not_to include('webhook_token', 'channel_id')
    end
  end

  it 'answers 401 to a wrong token, an unknown channel and an inbox of another provider alike' do
    baileys = create(:channel_whatsapp, provider: 'baileys', sync_templates: false, validate_provider_config: false)

    post "/webhooks/whatsapp/zapi/#{channel.id}/wrong", params: { type: 'ReceivedCallback' }, as: :json
    expect(response).to have_http_status(:unauthorized)

    post '/webhooks/whatsapp/zapi/0/zapi-token', params: { type: 'ReceivedCallback' }, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "/webhooks/whatsapp/zapi/#{baileys.id}/#{baileys.provider_config['webhook_verify_token']}", params: { type: 'ReceivedCallback' }, as: :json
    expect(response).to have_http_status(:unauthorized)

    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
  end

  it 'answers 401 to an inbox that has no token yet' do
    channel.update_column(:provider_config, channel.provider_config.except('webhook_verify_token')) # rubocop:disable Rails/SkipsModelValidations

    post "/webhooks/whatsapp/zapi/#{channel.id}/anything", params: { type: 'ReceivedCallback' }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
  end
end
