module Whatsapp::BaileysHandlers::ConnectionUpdate
  include Whatsapp::BaileysHandlers::Helpers

  private

  def process_connection_update
    data = processed_params[:data]

    inbox.channel.with_lock do
      if stale_connection_event?(data)
        Rails.logger.warn(
          "Baileys stale connection.update discarded: epoch #{data[:epoch]} < #{inbox.channel.provider_connection['epoch']}"
        )
        next
      end

      inbox.channel.update_provider_connection!(provider_connection_payload(data))
      Rails.logger.error "Baileys connection error: #{data[:error]}" if data[:error].present?
    end
  end

  # NOTE: `connection` values
  #   - `close`: Never opened, or closed and no longer able to send/receive messages
  #   - `connecting`: In the process of connecting, expecting QR code to be read
  #   - `reconnecting`: Connection has been established, but not open (i.e. device is being linked for the first time, or Baileys server restart)
  #   - `open`: Open and ready to send/receive messages
  def provider_connection_payload(data)
    {
      connection: data[:connection] || inbox.channel.provider_connection['connection'],
      qr_data_url: data[:qrDataUrl] || nil,
      error: data[:error] ? I18n.t("errors.inboxes.channel.provider_connection.#{data[:error]}", default: data[:error].to_s.humanize) : nil,
      reachout_time_lock: reachout_time_lock_payload(data),
      # new_chat_cap never rides a connection.update (it arrives via message-capping.update / the
      # poll). update_provider_connection! replaces provider_connection wholesale, so without
      # carrying it forward here every connection.update would wipe the cap and flicker the banner
      # off until the next cap push/poll. Preserve the existing value; .compact omits it when unset.
      new_chat_cap: inbox.channel.provider_connection['new_chat_cap'],
      epoch: data[:epoch]
    }.compact
  end

  # Reach-out time-lock is NOT echoed on every connection.update (the provider debounces it
  # ~60s and may push it standalone, without a `connection` value). So, unlike qr_data_url, a
  # connection-only event must PRESERVE the existing lock rather than reset it. When the
  # provider DOES send reachoutTimeLock (including isActive:false to lift the restriction), we
  # persist it verbatim — isActive:false is a real "cleared" state the UI relies on to drop the
  # banner. Returns nil only when nothing was ever set, so the outer .compact omits the key.
  def reachout_time_lock_payload(data)
    raw = data[:reachoutTimeLock]
    return inbox.channel.provider_connection['reachout_time_lock'] if raw.blank?

    {
      is_active: raw[:isActive] || false,
      time_enforcement_ends: raw[:timeEnforcementEnds],
      enforcement_type: raw[:enforcementType]
    }.compact
  end

  # In a multi-instance baileys-api deployment, ownership of a phone number
  # moves between instances (failover, rebalance, rolling deploys). Each
  # connection.update carries the lease epoch of its sender; events from a
  # previous owner can arrive late (webhook retries) and must not overwrite
  # the current owner's state — last-writer-wins here would leave the inbox
  # stuck on a stale "reconnecting" while the connection is actually open.
  # Events without an epoch (older baileys-api versions) are always accepted.
  def stale_connection_event?(data)
    return false if data[:epoch].blank?

    last_epoch = inbox.channel.provider_connection['epoch']
    return false if last_epoch.blank?

    data[:epoch].to_i < last_epoch.to_i
  end
end
