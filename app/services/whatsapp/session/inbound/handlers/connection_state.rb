# Everything that changes what the inbox reports about its WhatsApp connection: the
# state itself, the pairing steps, and the ways a session dies.
#
# One handler for all of them because they write the same record, through the only
# writer allowed to touch it. The i18n key in `error` is what the dashboard renders;
# a provider message never reaches the UI.
class Whatsapp::Session::Inbound::Handlers::ConnectionState < Whatsapp::Session::Inbound::Handlers::Base
  Events = Whatsapp::Session::Model::Events

  def perform
    state = build_state
    return :ignored if state.nil?

    result = Whatsapp::Session::ConnectionStateWriter.new(channel).apply(state)
    after_write(state) if result == :written
    result == :stale ? :ignored : :handled
  end

  private

  # Every event that only means "the session closed, and here is why" maps straight to
  # its i18n key; the rest need a little more than that.
  CLOSING_ERRORS = {
    Events::SessionLoggedOut => 'logged_out',
    Events::SessionStreamReplaced => 'stream_replaced',
    Events::SessionTemporaryBan => 'temporary_ban',
    Events::SessionClientOutdated => 'client_outdated',
    Events::SessionConnectFailure => 'connect_failure',
    Events::PairingError => 'connect_failure'
  }.freeze

  def build_state
    error = CLOSING_ERRORS[payload.class]
    return closed(error, ban: payload.try(:ban)) if error

    case payload
    when Events::SessionState then session_state
    when Events::PairingQr then connecting(qr_data_url: payload.png_data_url)
    when Events::PairingCode then connecting(pairing_code: payload.code)
    when Events::PairingSuccess then pairing_success
    end
  end

  def session_state
    state(payload.state, error: payload.reason, phone_number: payload.phone, lid: payload.lid,
                         quarantine: payload.quarantine, ban: payload.ban)
  end

  def pairing_success
    return closed('wrong_phone_number') if wrong_phone?

    connecting(phone_number: payload.phone, lid: payload.lid)
  end

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

  # The operator scanned the QR with a different number than the inbox is configured
  # for. Keeping that session would file the wrong contacts under this inbox, so it is
  # dropped and the inbox says why.
  #
  # Compared through the normalizers, never as raw digits: a Brazilian line is reported
  # by WhatsApp with or without the ninth digit depending on when it was registered, so
  # a textual comparison would reject the very number the operator configured.
  def wrong_phone?
    configured = channel.phone_number.to_s
    paired = payload.phone.to_s
    configured.present? && paired.present? && !Whatsapp::Session::PhoneMatch.same_number?(configured, paired)
  end

  def after_write(state)
    logout_wrong_number if state.error == 'wrong_phone_number'
  end

  def logout_wrong_number
    channel.provider_service.logout
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.warn("[WHATSAPP SESSION] logout after wrong number failed for inbox #{inbox.id}: #{e.message}")
  end
end
