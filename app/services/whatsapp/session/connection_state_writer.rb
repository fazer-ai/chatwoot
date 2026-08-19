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
  #
  # `attempt:` fences the write to one pairing attempt and `provider:` to the provider the
  # caller was built for. Both are checked inside the lock, which is the only place they
  # mean anything: a caller that reads the record, then asks the provider, then writes,
  # has left a gap in the middle for a second connect or a conversion to land in.
  def apply(state, reset: false, attempt: nil, provider: nil)
    written = nil

    result = channel.with_lock do
      # Inside the lock, because `with_lock` is also what reloads the row. Deciding
      # ownership against the caller's copy means a poll that started before a concurrent
      # event quarantined the inbox reads the pre-quarantine record and clears it.
      written = enforce_number_ownership(state, reset: reset)
      persisted = channel.provider_connection.presence || {}
      next :stale if refuse?(written, persisted, attempt: attempt, provider: provider)

      payload = merge(written, persisted)
      next :unchanged if payload == persisted

      channel.update_provider_connection!(payload)
      :written
    end

    # Through a job, not inline: a logout that failed once inline would never be attempted
    # a second time, and the wrong WhatsApp account would stay connected.
    #
    # Queued on an unchanged state as well as a written one, because queueing happens
    # after the commit. An attempt that wrote the quarantine and then failed to reach the
    # job transport leaves the state in place, so every repeat of it is reported as
    # unchanged and the logout is never asked for again. The job re-reads the quarantine
    # and stands down when it is gone, so asking twice costs nothing.
    ensure_logout(written) if %i[written unchanged].include?(result)
    result
  end

  private

  def ensure_logout(written)
    return unless written.error == WRONG_PHONE_ERROR

    Whatsapp::Session::LogoutJob.perform_later(channel)
  end

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
    carry_attempt(payload, persisted)
    return payload.except!(*PAIRING_KEYS) if PAIRING_ENDED.include?(payload['error_code'])

    PAIRING_KEYS.each { |key| payload[key] = persisted[key] if payload[key].nil? && persisted[key].present? }
  end

  # The token identifying the pairing attempt in progress. Only the connect answer and the
  # poll carry one, and every other event about the same attempt (a rotated QR, a pairing
  # code, a connecting state) arrives without it: dropping it there retires the polling
  # chain that is driving the very screen those events are updating, and the code on it
  # stops rotating. Kept while the attempt is still connecting, gone once it resolved.
  def carry_attempt(payload, persisted)
    return if payload['pairing_attempt'].present?
    return unless payload['connection'].in?(%w[connecting reconnecting])

    payload['pairing_attempt'] = persisted['pairing_attempt'] if persisted['pairing_attempt'].present?
  end

  # Three ways a state arrives too late to be true: the inbox is on another provider now,
  # the pairing it belongs to has been retired, or an older owner of the session is still
  # talking.
  def refuse?(state, persisted, attempt:, provider:)
    converted?(provider) || superseded?(attempt, persisted) || stale?(state, persisted)
  end

  # The record has moved on from the pairing attempt this write belongs to, so it is an
  # older connect or an older poll answering late: its QR is not the one the operator is
  # looking at, and the chain driving that screen would be retired by it. A record with no
  # token at all counts as moved on, because the token is only ever absent once the
  # attempt it named has ended. Epoch does not cover this: two connects on the same
  # session raise it in the order the provider answers, and a backend without an ownership
  # model (Uazapi) has no epoch at all.
  def superseded?(attempt, persisted)
    return false if attempt.blank?

    superseded = persisted['pairing_attempt'] != attempt
    Rails.logger.warn("[WHATSAPP SESSION] write for a retired pairing attempt discarded on ##{channel.id}") if superseded
    superseded
  end

  # The inbox was converted while this write was in flight. `convert_provider!` empties the
  # connection record, so what would land here is one provider's state under another
  # provider's name: a QR nobody can scan, or an `open` for a session this inbox no longer
  # has.
  def converted?(provider)
    return false if provider.blank?

    converted = channel.provider != provider
    Rails.logger.warn("[WHATSAPP SESSION] #{provider} state discarded on ##{channel.id}, now #{channel.provider}") if converted
    converted
  end

  # Events without an epoch (Uazapi, which has no ownership model) are always accepted.
  def stale?(state, persisted)
    return false if state.epoch.blank? || persisted['epoch'].blank?

    stale = state.epoch.to_i < persisted['epoch'].to_i
    Rails.logger.warn("[WHATSAPP SESSION] stale connection state discarded: epoch #{state.epoch} < #{persisted['epoch']}") if stale
    stale
  end
end
