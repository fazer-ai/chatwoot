require 'rails_helper'

RSpec.describe Webhooks::WhatsappSessionEventsJob do
  subject(:job) { described_class }

  let(:channel) { create(:channel_whatsapp, provider: 'uazapi', sync_templates: false, validate_provider_config: false) }
  let(:dispatcher) { Whatsapp::Session::Inbound::Dispatcher }
  let(:body) { JSON.parse(Rails.root.join('spec/fixtures/whatsapp/session/uazapi/webhook/message_incoming_text.json').read) }

  it 'dispatches what the body translates to' do
    allow(dispatcher).to receive(:dispatch).and_return(:handled)

    job.perform_now(channel, body)

    expect(dispatcher).to have_received(:dispatch).with(channel, having_attributes(type: 'message.received'))
  end

  # A body this build cannot read produces nothing, which is what lets the provider send
  # an event type Chatwoot has never heard of without the inbox failing on every delivery.
  it 'does nothing with an event type it does not translate' do
    allow(dispatcher).to receive(:dispatch)

    job.perform_now(channel, { 'EventType' => 'labels' })

    expect(dispatcher).not_to have_received(:dispatch)
  end

  # Converted while the body sat in the queue: this provider's events are not this
  # inbox's business any more, and there is no translator to read them with.
  it 'does nothing for an inbox that has left the session layer' do
    allow(dispatcher).to receive(:dispatch)
    channel.update_column(:provider, 'whatsapp_cloud') # rubocop:disable Rails/SkipsModelValidations

    job.perform_now(channel, body)

    expect(dispatcher).not_to have_received(:dispatch)
  end

  # The webhook has no ordering guarantee and the payloads carry nothing to rebuild one
  # from, so a handler that cannot find the message its event is about asks to be run
  # again rather than dropping the edit, the revoke or the reaction for good.
  describe 'when the event arrived before the message it refers to' do
    before { allow(dispatcher).to receive(:dispatch).and_return(:deferred) }

    it 'comes back later instead of dropping it' do
      expect { job.perform_now(channel, body) }.to have_enqueued_job(described_class)
    end
  end

  # A shape this build cannot parse is a provider or contract problem, and running it
  # again produces the same nothing.
  it 'drops a payload it cannot read rather than retrying it' do
    allow(dispatcher).to receive(:dispatch).and_raise(Whatsapp::Session::Errors::InvalidPayload, 'bad shape')

    expect { job.perform_now(channel, body) }.not_to have_enqueued_job(described_class)
  end
end
