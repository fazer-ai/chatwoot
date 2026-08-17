require 'rails_helper'

RSpec.describe Whatsapp::Session::ConnectionStateWriter do
  subject(:writer) { described_class.new(channel) }

  let(:channel) { create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false, sync_templates: false) }
  let(:state) { Whatsapp::Session::Model::ConnectionState }

  it 'writes the state and broadcasts it' do
    expect(writer.apply(state.new(connection: 'connecting', qr_data_url: 'data:image/png;base64,AAA', epoch: 3))).to eq(:written)

    expect(channel.reload.provider_connection).to include('connection' => 'connecting', 'epoch' => 3)
  end

  it 'clears what the new state does not carry' do
    writer.apply(state.new(connection: 'connecting', qr_data_url: 'data:image/png;base64,AAA', epoch: 3))
    writer.apply(state.new(connection: 'open', epoch: 3))

    expect(channel.reload.provider_connection).not_to have_key('qr_data_url')
  end

  it 'keeps the sticky account limits across a state change' do
    channel.update_reachout_time_lock!({ 'is_active' => true })
    channel.update_new_chat_cap!({ 'capping_status' => 'ACTIVE' })

    writer.apply(state.new(connection: 'open', epoch: 2))

    expect(channel.reload.provider_connection).to include(
      'reachout_time_lock' => { 'is_active' => true },
      'new_chat_cap' => { 'capping_status' => 'ACTIVE' }
    )
  end

  it 'discards an event from a previous lease owner' do
    writer.apply(state.new(connection: 'open', epoch: 5))

    expect(writer.apply(state.new(connection: 'reconnecting', epoch: 4))).to eq(:stale)
    expect(channel.reload.provider_connection['connection']).to eq('open')
  end

  it 'accepts a state without an epoch, for providers with no ownership model' do
    writer.apply(state.new(connection: 'open', epoch: 5))

    expect(writer.apply(state.new(connection: 'close'))).to eq(:written)
    expect(channel.reload.provider_connection).to include('connection' => 'close', 'epoch' => 5)
  end

  it 'does not rewrite an unchanged state' do
    writer.apply(state.new(connection: 'open', epoch: 1))

    expect(writer.apply(state.new(connection: 'open', epoch: 1))).to eq(:unchanged)
  end
end
