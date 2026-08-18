# Drives the pairing screen for backends that have to be polled.
#
# A QR rotates about every 20 seconds and the provider's webhook is not guaranteed to
# push every rotation, so the operator would be left staring at a code that stopped
# working. This job pulls the state until the session opens, the pairing is abandoned,
# or the ceiling below is reached.
class Whatsapp::Session::PairingPollJob < ApplicationJob
  queue_as :high

  INTERVAL = 15.seconds
  # A QR expires far sooner than a pairing code, which the operator has to type on the
  # phone. Both are ceilings on the whole attempt, not on a single code.
  DEADLINES = { 'qr' => 2.minutes, 'code' => 5.minutes }.freeze

  # `pairing` is the mode the connect command asked for; `deadline_at` is set on the first
  # run and carried forward so re-enqueueing never extends the ceiling. `provider` is the
  # provider that started this pairing: an inbox converted while a poll sat in the queue
  # would otherwise be polled, and failed, against whatever it became.
  def perform(channel, pairing: 'qr', deadline_at: nil, provider: nil)
    @channel = channel
    @pairing = pairing.to_s
    @provider = provider || channel.provider
    @deadline_at = deadline_at || (Time.current + DEADLINES.fetch(@pairing, DEADLINES['qr']))
    return unless channel.provider == @provider

    backend = channel.session_backend
    poll(backend) if backend.class.state_polling?
  rescue Whatsapp::Session::Errors::Error => e
    # The instance being unreachable mid-pairing is the operator's problem to see on the
    # screen, not something a retry storm fixes: the next connect starts a fresh poll.
    Rails.logger.warn("[WHATSAPP SESSION] pairing poll failed for ##{channel.id}: #{e.message}")
    give_up('connect_failure')
  end

  private

  attr_reader :channel, :pairing, :provider, :deadline_at

  def poll(backend)
    state = backend.fetch_connection_state
    Whatsapp::Session::ConnectionStateWriter.new(channel).apply(state)
    return if settled?(state)
    return give_up('pairing_timed_out') if Time.current + INTERVAL >= deadline_at

    self.class.set(wait: INTERVAL).perform_later(channel, pairing: pairing, deadline_at: deadline_at, provider: provider)
  end

  # Both ways a pairing ends without succeeding write the reason to the connection record.
  # Leaving the last `connecting` state in place parks the dashboard on a QR that expired
  # minutes ago, waiting for a rotation that is never coming.
  def give_up(error)
    Whatsapp::Session::ConnectionStateWriter.new(channel).apply(
      Whatsapp::Session::Model::ConnectionState.new(connection: 'close', error: error)
    )
  end

  # Anything that is not still trying to connect ends the poll: `open` means paired, and
  # a closed connection means the attempt was abandoned or refused. `reconnecting` is
  # the provider still working on it, which is exactly when the poll is needed: the QR
  # keeps rotating and the push that would carry it is the thing this job exists to
  # replace, so treating it as settled leaves the operator on a dead code.
  def settled?(state)
    !state.connecting?
  end
end
