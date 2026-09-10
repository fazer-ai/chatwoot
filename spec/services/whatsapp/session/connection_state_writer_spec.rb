require 'rails_helper'

RSpec.describe Whatsapp::Session::ConnectionStateWriter do
  subject(:writer) { described_class.new(channel) }

  let(:channel) { create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false, sync_templates: false) }
  let(:state) { Whatsapp::Session::Model::ConnectionState }

  it 'writes the state and broadcasts it' do
    expect(writer.apply(state.new(connection: 'connecting', qr_data_url: 'data:image/png;base64,AAA', epoch: 3))).to eq(:written)

    expect(channel.reload.provider_connection).to include('connection' => 'connecting', 'epoch' => 3)
  end

  # Every reason the connector puts on a closing `session.state`, taken from
  # `publishPairingFailure` and the `EventSessionState` emits in
  # `internal/engine/whatsmeow/session.go`. A key that is missing does not fail anywhere:
  # it renders as the humanized key, in English, in every locale. `pairing_timeout` did
  # exactly that while a written sentence for the same failure sat under
  # `pairing_timed_out`, which nothing sends.
  %w[
    connect_failed disconnect_requested disconnected
    pairing_timeout pairing_pair_error pairing_err-scanned-without-multidevice
    pairing_code_refused pairing_connect_failed
  ].each do |reason|
    it "has a sentence written for #{reason}" do
      writer.apply(state.new(connection: 'close', error: reason, epoch: 3))

      expect(channel.reload.provider_connection['error']).not_to eq(reason.humanize)
    end
  end

  # The placeholder still stands, because a blank is worse. What it must not do is stand
  # in silence: this is the only thing that says a provider started sending something
  # nobody wrote a sentence for.
  it 'says out loud when a reason has no sentence' do
    allow(Rails.logger).to receive(:warn)
    writer.apply(state.new(connection: 'close', error: 'a_reason_nobody_wrote', epoch: 3))

    expect(Rails.logger).to have_received(:warn).with(/no sentence written.*a_reason_nobody_wrote/)
    expect(channel.reload.provider_connection['error']).to eq('A reason nobody wrote')
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

  # A history request travels to the phone through the session, so a session that ends
  # takes any outstanding request with it. Without this the dump that follows the next
  # pairing would be filed as if somebody had asked for it, and tuning the window's length
  # to make that unlikely is a worse answer than removing the case.
  describe 'an outstanding history backfill' do
    let(:backfill) { Whatsapp::Session::HistoryBackfill }

    before { backfill.open!(channel) }

    it 'is closed when the session is no longer open' do
      writer.apply(Whatsapp::Session::Model::ConnectionState.new(connection: 'close'))

      expect(backfill.pending?(channel)).to be(false)
    end

    it 'survives a state that reports the session up' do
      writer.apply(Whatsapp::Session::Model::ConnectionState.new(connection: 'open', phone_number: channel.phone_number))

      expect(backfill.pending?(channel)).to be(true)
    end
  end
end
