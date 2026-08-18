# The only writer of channel_whatsapp.provider_connection for session providers.
#
# Three rules live here, all of them learned from the Baileys layer:
#   1. Ownership fencing: a late event from a previous owner (lower lease epoch) must not
#      overwrite the current owner's state, or the inbox gets stuck reporting a stale
#      status while the connection is actually open.
#   2. Whole-hash replacement: qr_data_url, pairing_code, error and quarantine share the
#      lifecycle of the state they arrived with, so anything the new state does not carry
#      is cleared.
#   3. Sticky keys: reach-out lock and new-chat cap arrive out of band (poll or their own
#      event), so they survive a state update instead of flickering off until the next poll.
class Whatsapp::Session::ConnectionStateWriter
  STICKY_KEYS = Whatsapp::Session::Model::ConnectionState::STICKY_KEYS

  attr_reader :channel

  def initialize(channel)
    @channel = channel
  end

  # Returns :written, :stale or :unchanged.
  def apply(state)
    channel.with_lock do
      persisted = channel.provider_connection.presence || {}
      next :stale if stale?(state, persisted)

      payload = merge(state, persisted)
      next :unchanged if payload == persisted

      channel.update_provider_connection!(payload)
      :written
    end
  end

  private

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

  # Events without an epoch (Uazapi, which has no ownership model) are always accepted.
  def stale?(state, persisted)
    return false if state.epoch.blank? || persisted['epoch'].blank?

    stale = state.epoch.to_i < persisted['epoch'].to_i
    Rails.logger.warn("[WHATSAPP SESSION] stale connection state discarded: epoch #{state.epoch} < #{persisted['epoch']}") if stale
    stale
  end
end
