# The only writer of channel_whatsapp.provider_connection for session providers.
#
# Four rules live here, all of them learned from the Baileys layer:
#   1. Ownership fencing: a late event from a previous owner (lower lease epoch) must not
#      overwrite the current owner's state, or the inbox gets stuck reporting a stale
#      status while the connection is actually open.
#   2. Number ownership: a session paired with a number this inbox is not configured for
#      is somebody else's WhatsApp account, and no state may report it as usable.
#   3. Whole-hash replacement: qr_data_url, pairing_code, error and quarantine share the
#      lifecycle of the state they arrived with, so anything the new state does not carry
#      is cleared.
#   4. Sticky keys: reach-out lock and new-chat cap arrive out of band (poll or their own
#      event), so they survive a state update instead of flickering off until the next poll.
#
# Rule 2 lives here rather than in the event handler because a handler is only one of the
# ways a state is written: the pairing poll and the connect answer write one directly, and
# a check on the handler leaves those two admitting the wrong account.
class Whatsapp::Session::ConnectionStateWriter
  STICKY_KEYS = Whatsapp::Session::Model::ConnectionState::STICKY_KEYS

  # The session was paired with a number this inbox is not configured for. Written here,
  # read by everything that has to keep the wrong account's chats out until the logout
  # succeeds, so the three places that used to spell it out cannot drift apart.
  WRONG_PHONE_ERROR = 'wrong_phone_number'.freeze

  # Which number this session is paired with is not part of the connection lifecycle: a
  # close does not un-pair anything, and the provider still holds the credentials.
  # Clearing these on every close is what would make the next connect ask for a QR rather
  # than resume, so a transient disconnect would cost the operator a fresh scan.
  PAIRING_KEYS = %w[phone_number lid].freeze

  # The two ways a pairing really ends. Everything else is a connection that may come back.
  PAIRING_ENDED = [WRONG_PHONE_ERROR, 'logged_out'].freeze

  # Quarantined: the connection belongs to somebody else's WhatsApp account.
  def self.disowned?(channel)
    channel.provider_connection.to_h['error_code'] == WRONG_PHONE_ERROR
  end

  attr_reader :channel

  def initialize(channel)
    @channel = channel
  end

  # Returns :written, :stale or :unchanged.
  #
  # `reset: true` means the operator asked for this connection: a quarantine from the
  # previous pairing does not carry over, because re-pairing is the way out of one.
  def apply(state, reset: false)
    state = enforce_number_ownership(state, reset: reset)

    result = channel.with_lock do
      persisted = channel.provider_connection.presence || {}
      next :stale if stale?(state, persisted)

      payload = merge(state, persisted)
      next :unchanged if payload == persisted

      channel.update_provider_connection!(payload)
      :written
    end

    # Through a job, not inline. The state is already written when this runs, so a repeat
    # of the same state is reported as unchanged and never gets here again: a logout that
    # failed once inline would never be attempted a second time, and the wrong WhatsApp
    # account would stay connected.
    Whatsapp::Session::LogoutJob.perform_later(channel) if result == :written && state.error == WRONG_PHONE_ERROR
    result
  end

  private

  # Two ways a state can belong to the wrong account. It can name the wrong number, which
  # is the operator having scanned with a different phone. Or it can name no number at all
  # while the inbox is already quarantined: `session.state` only requires `state`, so a
  # live session reports itself without saying whose it is, and accepting one of those
  # would clear the quarantine while the logout that removes that account is still being
  # retried. Only a state that names the configured number lifts it.
  def enforce_number_ownership(state, reset:)
    return quarantine(state) if wrong_phone?(state)
    return state if reset || state.phone_number.present?
    return state unless self.class.disowned?(channel)

    quarantine(state)
  end

  def quarantine(state)
    Whatsapp::Session::Model::ConnectionState.new(
      connection: 'close', error: WRONG_PHONE_ERROR, epoch: state.epoch
    )
  end

  # Compared through the normalizers, never as raw digits: a Brazilian line is reported by
  # WhatsApp with or without the ninth digit depending on when it was registered, so a
  # textual comparison would reject the very number the operator configured.
  def wrong_phone?(state)
    configured = channel.phone_number.to_s
    paired = state.phone_number.to_s
    configured.present? && paired.present? && !Whatsapp::Session::PhoneMatch.same_number?(configured, paired)
  end

  def merge(state, persisted)
    payload = state.to_h
    # The sentence is what the dashboard renders, and the key is what code compares
    # against: the sentence depends on the locale in force when it was written and on
    # the translation not having been reworded since, so a guard reading it would fail
    # open without anybody noticing.
    if payload['error'].present?
      payload['error_code'] = payload['error']
      payload['error'] = translate(payload['error'])
    end
    payload['connection'] ||= persisted['connection']
    payload['epoch'] ||= persisted['epoch']
    carry_pairing(payload, persisted)
    STICKY_KEYS.each do |key|
      payload[key] = persisted[key] if payload[key].nil? && persisted[key].present?
    end
    payload.compact
  end

  # The wire carries an i18n key; what is persisted is the sentence. Resolving here rather
  # than on read is what keeps the REST payload and the Action Cable push identical: a
  # broadcast has no single reader whose locale could be used, so translating on read
  # would hand every administrator the locale of whichever job happened to emit the
  # event, and the live update would then overwrite a correctly localized REST value with
  # it. This matches what the Baileys handler has always done.
  def translate(key)
    I18n.t("errors.inboxes.channel.provider_connection.#{key}", default: key.to_s.humanize)
  end

  def carry_pairing(payload, persisted)
    return payload.except!(*PAIRING_KEYS) if PAIRING_ENDED.include?(payload['error_code'])

    PAIRING_KEYS.each { |key| payload[key] = persisted[key] if payload[key].nil? && persisted[key].present? }
  end

  # Events without an epoch (Uazapi, which has no ownership model) are always accepted.
  def stale?(state, persisted)
    return false if state.epoch.blank? || persisted['epoch'].blank?

    stale = state.epoch.to_i < persisted['epoch'].to_i
    Rails.logger.warn("[WHATSAPP SESSION] stale connection state discarded: epoch #{state.epoch} < #{persisted['epoch']}") if stale
    stale
  end
end
