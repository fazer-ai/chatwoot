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

  # `pairing` is the mode the connect command asked for; `deadline_at` is set on the
  # first run and carried forward so re-enqueueing never extends the ceiling.
  def perform(channel, pairing: 'qr', deadline_at: nil)
    deadline_at ||= Time.current + DEADLINES.fetch(pairing.to_s, DEADLINES['qr'])
    backend = channel.session_backend
    return unless backend.class.state_polling?

    state = backend.fetch_connection_state
    Whatsapp::Session::ConnectionStateWriter.new(channel).apply(state)
    return if settled?(state) || Time.current + INTERVAL >= deadline_at

    self.class.set(wait: INTERVAL).perform_later(channel, pairing: pairing, deadline_at: deadline_at)
  rescue Whatsapp::Session::Errors::Error => e
    # The instance being unreachable mid-pairing is the operator's problem to see on the
    # screen, not something a retry storm fixes: the next connect starts a fresh poll.
    # Said on the screen, though, and not only in the log: leaving the state untouched
    # parks the dashboard on a QR that expired minutes ago, waiting for a rotation that
    # is never coming.
    Rails.logger.warn("[WHATSAPP SESSION] pairing poll failed for ##{channel.id}: #{e.message}")
    Whatsapp::Session::ConnectionStateWriter.new(channel).apply(
      Whatsapp::Session::Model::ConnectionState.new(connection: 'close', error: 'connect_failure')
    )
  end

  private

  # Anything that is not still trying to connect ends the poll: `open` means paired, and
  # a closed connection means the attempt was abandoned or refused. `reconnecting` is
  # the provider still working on it, which is exactly when the poll is needed: the QR
  # keeps rotating and the push that would carry it is the thing this job exists to
  # replace, so treating it as settled leaves the operator on a dead code.
  def settled?(state)
    !state.connecting?
  end
end
