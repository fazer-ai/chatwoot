# Backs the new `Channel::Simulator` channel type. Accounts with
# `environment = test` auto-create one of these and a matching Inbox named
# "Simulador" (handled by Account#ensure_simulator_inbox!). The simulator
# widget rendered in Phase 4-5 will authenticate against this channel via the
# same public widget controllers used by `Channel::WebWidget`, so the
# `website_token` field mirrors what those controllers look up.
class CreateChannelSimulator < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_simulator do |t|
      t.integer :account_id, null: false
      t.string :website_token
      t.string :pubsub_token

      t.timestamps
    end

    add_index :channel_simulator, :website_token, unique: true
    add_index :channel_simulator, :pubsub_token, unique: true
    add_index :channel_simulator, :account_id
  end
end
