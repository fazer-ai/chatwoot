module Whatsapp::BaileysHandlers::ConnectionUpdate
  include Whatsapp::BaileysHandlers::Helpers

  private

  # NOTE: `connection` values
  #   - `close`: Never opened, or closed and no longer able to send/receive messages
  #   - `connecting`: In the process of connecting, expecting QR code to be read
  #   - `reconnecting`: Connection has been established, but not open (i.e. device is being linked for the first time, or Baileys server restart)
  #   - `open`: Open and ready to send/receive messages
  def process_connection_update
    data = processed_params[:data]
    current = inbox.channel.provider_connection || {}

    next_connection = data[:connection] || current['connection']

    payload = {
      connection: next_connection,
      qr_data_url: resolve_qr_data_url(data, current, next_connection),
      error: translate_baileys_error(data[:error])
    }.compact
    # `history_import` lives alongside `connection` in the same JSONB. Since
    # `update_provider_connection!` REPLACES the column (not merge), we have
    # to carry the snapshot forward or the history-import card disappears
    # the next time Baileys re-emits a connection_update event (typing, QR
    # rotation, reconnect).
    payload[:history_import] = current['history_import'] if current['history_import'].present?

    inbox.channel.update_provider_connection!(payload)

    Rails.logger.error "Baileys connection error: #{data[:error]}" if data[:error].present?
  end

  # Baileys emits multiple connection_update events per pairing session and only some carry
  # `qrDataUrl`. Preserve the previous QR while we are still connecting so the modal does not
  # flicker between QR and spinner; clear it whenever the connection leaves the connecting state.
  def resolve_qr_data_url(data, current, next_connection)
    return data[:qrDataUrl] if data[:qrDataUrl].present?
    return current['qr_data_url'] if next_connection == 'connecting'

    nil
  end

  def translate_baileys_error(error_key)
    return nil if error_key.blank?

    I18n.t("errors.inboxes.channel.provider_connection.#{error_key}")
  end
end
