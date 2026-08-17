# The connection-check scheduler finds channels to poll by querying provider_connection,
# and the session providers (native, uazapi) are polled exactly like the legacy ones. The
# partial index has to cover them or those queries fall back to a sequential scan.
#
# Both halves are concurrent. A plain DROP INDEX takes an ACCESS EXCLUSIVE lock and
# queues every read and write on channel_whatsapp behind whatever transaction is already
# holding the table, which on a live install is a stall in the middle of a deploy.
class ExtendWhatsappProviderConnectionIndexToSessionProviders < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_provider_connection', if_exists: true, algorithm: :concurrently

    add_index :channel_whatsapp, :provider_connection,
              using: :gin,
              where: "provider IN ('baileys', 'zapi', 'native', 'uazapi')",
              name: 'index_channel_whatsapp_provider_connection',
              algorithm: :concurrently
  end

  def down
    remove_index :channel_whatsapp, name: 'index_channel_whatsapp_provider_connection', if_exists: true, algorithm: :concurrently

    add_index :channel_whatsapp, :provider_connection,
              using: :gin,
              where: "provider IN ('baileys', 'zapi')",
              name: 'index_channel_whatsapp_provider_connection',
              algorithm: :concurrently
  end
end
