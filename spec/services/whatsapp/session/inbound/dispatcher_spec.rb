require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Dispatcher do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:model) { Whatsapp::Session::Model }

  it 'routes every canonical type to a handler or to the ignore list' do
    routed = described_class::HANDLERS.keys + described_class::IGNORED

    expect(model::Events::TYPES - routed).to be_empty
  end

  # The table holds names rather than classes, so a typo would otherwise only surface
  # the day that event arrives. This keeps it a load-time guarantee.
  it 'names a handler that exists for every type it routes' do
    missing = described_class::HANDLERS.values.uniq.reject do |name|
      "Whatsapp::Session::Inbound::Handlers::#{name}".safe_constantize.present?
    end

    expect(missing).to be_empty
  end

  # An added type is additive, so it ships on the same protocol major. A frame on a
  # major this build does not read is refused earlier, by the parser.
  it 'ignores a type this build does not know instead of failing the shard' do
    event = model::Event.from_frame({ 'v' => 1, 'type' => 'session.teleported', 'payload' => { 'anything' => true } })

    expect(described_class.dispatch(channel, event)).to eq(:ignored)
  end

  it 'ignores a type the catalog knows but this layer does not act on' do
    event = model::Event.build(model::Events::HistorySync.new(kind: 'recent', progress: 10))

    expect(described_class.dispatch(channel, event)).to eq(:ignored)
  end

  it 'hands the event to the handler of its type' do
    event = model::Event.build(model::Events::SessionState.new(state: 'open'))

    expect(described_class.dispatch(channel, event)).to eq(:handled)
    expect(channel.reload.provider_connection['connection']).to eq('open')
  end
end
