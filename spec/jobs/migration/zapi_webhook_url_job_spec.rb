require 'rails_helper'

RSpec.describe Migration::ZapiWebhookUrlJob do
  let(:zapi_config) { { 'instance_id' => 'instance', 'token' => 'zapi-api-token', 'client_token' => 'client' } }
  let(:legacy) { create(:channel_whatsapp, provider: 'zapi', provider_config: zapi_config, validate_provider_config: false, sync_templates: false) }
  let(:moved) do
    create(:channel_whatsapp, provider: 'zapi', validate_provider_config: false, sync_templates: false).tap do |channel|
      channel.provider_config = zapi_config.merge('webhook_verify_token' => 'already', 'webhook_url_confirmed_for' => 'instance')
      channel.save!(validate: false)
    end
  end
  let(:webhooks_url) { "#{Whatsapp::Providers::WhatsappZapiService::API_BASE_PATH}/instances/instance/token/zapi-api-token/update-every-webhooks" }

  it 'moves an inbox still on the old URL and leaves a moved one alone' do
    legacy
    moved
    stub_request(:put, webhooks_url).to_return(status: 200)

    expect(described_class.perform_now).to eq(moved: 1, failed: 0)
    expect(legacy.reload.provider_config).to include('webhook_url_confirmed_for' => 'instance')
    expect(moved.reload.provider_config['webhook_verify_token']).to eq('already')
    expect(a_request(:put, webhooks_url)).to have_been_made.once
  end

  # An inbox it cannot reach stays on the old URL, which keeps taking its events.
  it 'leaves an inbox it cannot reach on the old URL and carries on' do
    legacy
    stub_request(:put, webhooks_url).to_return(status: 500, body: 'down')
    allow(Rails.logger).to receive(:warn)

    expect(described_class.perform_now).to eq(moved: 0, failed: 1)
    expect(legacy.reload.provider_config).not_to have_key('webhook_url_confirmed_for')
    expect(Rails.logger).to have_received(:warn).with(/still on the old URL channel_id=#{legacy.id}/)
  end
end
