require 'rails_helper'

RSpec.describe Integrations::Clickup::RegisterWebhookJob do
  let(:client) { instance_double(Integrations::Clickup::Client, configured?: true) }

  before do
    allow(Integrations::Clickup::Client).to receive(:new).and_return(client)
  end

  it 'does nothing when the ClickUp API key is not configured' do
    allow(client).to receive(:configured?).and_return(false)

    described_class.new.perform

    expect(client).not_to have_received(:create_webhook) if client.respond_to?(:create_webhook)
  end

  it 'registers the webhook against the Auris team with the events we consume' do
    allow(client).to receive(:create_webhook).and_return(
      'webhook' => { 'id' => 'hook-1', 'secret' => 'signed-with-this' }
    )
    allow(client).to receive(:delete_webhook)

    described_class.new.perform

    expect(client).to have_received(:create_webhook).with(
      team_id: Integrations::Clickup::FieldMap::TEAM_ID,
      endpoint: end_with('/webhooks/clickup'),
      events: Integrations::Clickup::FieldMap::WEBHOOK_EVENTS
    )
    expect(InstallationConfig.find_by(name: 'CLICKUP_WEBHOOK_ID').value).to eq('hook-1')
    expect(InstallationConfig.find_by(name: 'CLICKUP_WEBHOOK_SECRET').value).to eq('signed-with-this')
  end

  # A re-registration (admin rotated the API key or bumped FRONTEND_URL) must
  # clean up the previous webhook first — otherwise ClickUp keeps firing at
  # the stale endpoint and we double-process every event.
  it 'deletes the previous webhook before creating a new one when one is already registered' do
    InstallationConfig.where(name: 'CLICKUP_WEBHOOK_ID').first_or_create!(value: 'old-hook', locked: false)
    allow(client).to receive(:delete_webhook)
    allow(client).to receive(:create_webhook).and_return('webhook' => { 'id' => 'new-hook', 'secret' => 'new-secret' })

    described_class.new.perform

    expect(client).to have_received(:delete_webhook).with('old-hook')
  end

  # Fault tolerance: a stale webhook id (already deleted upstream) must not
  # block the registration of the fresh one.
  it 'proceeds with registration even if the delete of the previous webhook fails' do
    InstallationConfig.where(name: 'CLICKUP_WEBHOOK_ID').first_or_create!(value: 'old-hook', locked: false)
    allow(client).to receive(:delete_webhook).and_raise(Integrations::Clickup::Client::ProviderUnavailable, '404')
    allow(client).to receive(:create_webhook).and_return('webhook' => { 'id' => 'new-hook', 'secret' => 'new-secret' })

    expect { described_class.new.perform }.not_to raise_error
    expect(InstallationConfig.find_by(name: 'CLICKUP_WEBHOOK_ID').value).to eq('new-hook')
  end
end
