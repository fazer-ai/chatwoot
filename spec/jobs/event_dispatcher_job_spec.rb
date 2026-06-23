require 'rails_helper'

RSpec.describe EventDispatcherJob do
  subject(:job) { described_class.perform_later(event_name, timestamp, event_data) }

  let!(:conversation) { create(:conversation) }
  let(:event_name) { 'conversation.created' }
  let(:timestamp) { Time.zone.now }
  let(:event_data) { { conversation: conversation } }

  it 'queues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(event_name, timestamp, event_data)
      .on_queue('critical')
  end

  # Raw WhatsApp provider events flood the queue (especially Baileys
  # `presence.update`) and are only consumed by `WebhookListener` to
  # mirror payloads to external webhooks. We route them to `:low` so
  # they don't crowd out actual UI broadcasts/notifications on `:critical`.
  it 'routes provider.event_received to :low instead of :critical' do
    inbox = create(:inbox)
    expect do
      described_class.perform_later('provider.event_received', timestamp,
                                    { inbox: inbox, event: 'presence.update', payload: {} })
    end.to have_enqueued_job(described_class).on_queue('low')
  end

  it 'publishes event' do
    expect(Rails.configuration.dispatcher.async_dispatcher).to receive(:publish_event).with(event_name, timestamp, event_data).once
    event_dispatcher = described_class.new
    event_dispatcher.perform(event_name, timestamp, event_data)
  end
end
