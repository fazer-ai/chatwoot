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

  describe 'writes fenced to the caller they came from' do
    # The connect and the poll both read the record, ask the provider and then write, and
    # a second connect claiming the pairing lands in that gap. Checking before the call
    # cannot see it; the fence is read inside the lock that does the write.
    it 'refuses a write whose pairing attempt the record has moved past' do
      channel.update_provider_connection!({ 'connection' => 'connecting', 'pairing_attempt' => 'attempt-2' })

      result = writer.apply(state.new(connection: 'connecting', qr_data_url: 'data:image/png;base64,OLD'), attempt: 'attempt-1')

      expect(result).to eq(:stale)
      expect(channel.reload.provider_connection).not_to have_key('qr_data_url')
    end

    # A provider knows nothing about this token, so a state that arrives without one says
    # nothing about which pairing it belongs to and must not end the one in flight. The
    # case that proved it: pairing by code on Uazapi needs a disconnected instance, and the
    # webhook answering that disconnect lands after the connect that follows it.
    it 'keeps the attempt in flight when a late close arrives without one' do
      channel.update_provider_connection!({ 'connection' => 'connecting', 'pairing_attempt' => 'attempt-1',
                                            'pairing_code' => 'K7QP-2M4X' })

      expect(writer.apply(state.new(connection: 'close'))).to eq(:written)

      expect(channel.reload.provider_connection).to include('connection' => 'close', 'pairing_attempt' => 'attempt-1')
    end

    # Which is what makes the chain survive it: the poll that owns the screen reads the
    # record again on its next run and is still the one driving it.
    it 'lets the attempt that owns the screen write again after that close' do
      channel.update_provider_connection!({ 'connection' => 'connecting', 'pairing_attempt' => 'attempt-1' })
      writer.apply(state.new(connection: 'close'))

      result = writer.apply(state.new(connection: 'connecting', pairing_code: 'K7QP-2M4X'), attempt: 'attempt-1')

      expect(result).to eq(:written)
      expect(channel.reload.provider_connection).to include('pairing_code' => 'K7QP-2M4X')
    end

    # The token is only ever absent once the attempt it named is over, so a write still
    # carrying one is answering about a pairing that has already ended.
    it 'refuses a write for an attempt the record no longer names' do
      channel.update_provider_connection!({ 'connection' => 'open', 'phone_number' => '5541988887777' })

      result = writer.apply(state.new(connection: 'connecting'), attempt: 'attempt-1')

      expect(result).to eq(:stale)
      expect(channel.reload.provider_connection).to include('connection' => 'open')
    end

    # An inbox converted mid-connect has an empty record belonging to another provider,
    # and the old backend's answer would land in it as a QR nobody can scan.
    it 'refuses a write from the provider the inbox used to be on' do
      result = writer.apply(state.new(connection: 'connecting', qr_data_url: 'data:image/png;base64,OLD'), provider: 'uazapi')

      expect(result).to eq(:stale)
      expect(channel.reload.provider_connection).to eq({})
    end

    it 'writes when the inbox is still on the provider the caller was built for' do
      expect(writer.apply(state.new(connection: 'connecting'), provider: 'baileys')).to eq(:written)
    end
  end

  it 'does not rewrite an unchanged state' do
    writer.apply(state.new(connection: 'open', epoch: 1))

    expect(writer.apply(state.new(connection: 'open', epoch: 1))).to eq(:unchanged)
  end

  # The quarantine is written before the logout is queued, so an attempt that failed in
  # between leaves every repeat of the state reported as unchanged, and the account
  # Chatwoot refuses to keep would stay connected with nobody asking it to stop. The job
  # re-reads the quarantine and stands down when it is gone, so asking twice costs
  # nothing and never asking is unrecoverable.
  it 'asks for the logout again when the wrong number is reported a second time' do
    wrong = state.new(connection: 'open', phone_number: '5541988887777', epoch: 1)
    expect(writer.apply(wrong)).to eq(:written)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect(writer.apply(wrong)).to eq(:unchanged)

    expect(Whatsapp::Session::LogoutJob).to have_been_enqueued.with(channel)
  end
end
