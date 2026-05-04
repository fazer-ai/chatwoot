class AddReconnectionEnabledToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    # Nullable on purpose: nil is treated as "enabled" by Channel::Whatsapp#reconnection_enabled?,
    # so existing rows automatically inherit the previous behavior with no backfill.
    add_column :channel_whatsapp, :reconnection_enabled, :boolean # rubocop:disable Rails/ThreeStateBooleanColumn
  end
end
