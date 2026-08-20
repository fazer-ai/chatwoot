# Everything that changes what the inbox reports about its WhatsApp connection: the
# state itself, the pairing steps, and the ways a session dies.
#
# One handler for all of them because they write the same record, through the only
# writer allowed to touch it. The i18n key in `error` is what the dashboard renders;
# a provider message never reaches the UI.
class Whatsapp::Session::Inbound::Handlers::ConnectionState < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    state = build_state
    return :ignored if state.nil?

    # Fenced to the instance the event arrived from, and the writer compares it inside the
    # row lock: an inbox re-pointed after the dispatcher looked would otherwise take the
    # previous instance's state, down to the number it was paired with, which reads as the
    # wrong one and ends the session that just replaced it.
    result = Whatsapp::Session::ConnectionStateWriter.new(channel).apply(state, instance: instance)
    result == :stale ? :ignored : :handled
  end

  private

  # Every event that only means "the session closed, and here is why" maps straight to
  # its i18n key; the rest need a little more than that.
  #
  # Keyed by wire type rather than by event class. A class in a constant is captured when
  # this file loads, and after a reload the incoming payload is an instance of the new
  # generation: the lookup misses, the case below misses too, and the session state is
  # dropped without an error anywhere.
  CLOSING_ERRORS = {
    'session.logged_out' => 'logged_out',
    'session.stream_replaced' => 'stream_replaced',
    'session.temporary_ban' => 'temporary_ban',
    'session.client_outdated' => 'client_outdated',
    'session.connect_failure' => 'connect_failure',
    'pairing.error' => 'connect_failure'
  }.freeze

  def build_state
    type = payload&.wire_type
    error = CLOSING_ERRORS[type]
    return closed(error, ban: payload.try(:ban)) if error

    case type
    when 'session.state' then session_state
    when 'pairing.qr' then connecting(qr_data_url: payload.png_data_url)
    when 'pairing.code' then connecting(pairing_code: payload.code)
    when 'pairing.success' then pairing_success
    end
  end

  # Whose account this is, is not decided here: the writer refuses any state that names
  # the wrong number, or that names none while the inbox is quarantined, because the poll
  # and the connect answer write states without ever passing through a handler.
  def session_state
    state(payload.state, error: payload.reason, phone_number: payload.phone, lid: payload.lid,
                         quarantine: payload.quarantine, ban: payload.ban)
  end

  def pairing_success = connecting(phone_number: payload.phone, lid: payload.lid)

  def closed(error, **attributes) = state('close', error: error, **attributes)
  def connecting(**attributes) = state('connecting', **attributes)

  def state(connection, **attributes)
    model::ConnectionState.new(connection: connection, epoch: epoch, **attributes)
  end

  # Uazapi has no ownership model and sends no epoch; only the connector's epoch is a
  # real fencing token, and it starts at 1.
  def epoch
    event.epoch.to_i.positive? ? event.epoch.to_i : nil
  end
end
