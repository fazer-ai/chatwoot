# The provider connection as the UI sees it. Persisted as-is in
# channel_whatsapp.provider_connection by ConnectionStateWriter, keeping the shape the
# Baileys layer already writes so the dashboard needs no migration.
#
# `error` stores an i18n key suffix (resolved under
# `errors.inboxes.channel.provider_connection`), never a provider message.
class Whatsapp::Session::Model::ConnectionState < Data.define(
  :connection, :qr_data_url, :pairing_code, :error, :epoch, :phone_number, :lid,
  :quarantine, :ban, :reachout_time_lock, :new_chat_cap
)
  include Whatsapp::Session::Model::Serializable

  CONNECTIONS = %w[close connecting reconnecting open].freeze

  # Written by polls and by the provider outside the connection lifecycle, so a state
  # update must never drop them.
  STICKY_KEYS = %w[reachout_time_lock new_chat_cap].freeze

  def initialize(**attributes)
    connection = attributes[:connection].to_s
    raise Whatsapp::Session::Errors::InvalidPayload, "unknown connection: #{connection}" unless CONNECTIONS.include?(connection)

    super
  end

  def open?
    connection == 'open'
  end

  def close?
    connection == 'close'
  end

  def connecting?
    connection.in?(%w[connecting reconnecting])
  end
end
