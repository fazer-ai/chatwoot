class HardenDisparosPiiAndFkLifecycle < ActiveRecord::Migration[7.1]
  def up
    # M1: drop raw plaintext phone (PII) and keep only a presence boolean.
    remove_column :disparo_targets, :phone
    add_column :disparo_targets, :phone_present, :boolean, null: false, default: false

    # M2/M3: let core-entity deletion flow through Beta 0 instead of wedging on FKs.
    remove_foreign_key :disparo_inboxes, :inboxes
    add_foreign_key :disparo_inboxes, :inboxes, on_delete: :cascade

    remove_foreign_key :disparos, :accounts
    add_foreign_key :disparos, :accounts, on_delete: :cascade

    remove_foreign_key :disparos, :users, column: :created_by_id
    add_foreign_key :disparos, :users, column: :created_by_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :disparos, :users, column: :created_by_id
    add_foreign_key :disparos, :users, column: :created_by_id

    remove_foreign_key :disparos, :accounts
    add_foreign_key :disparos, :accounts

    remove_foreign_key :disparo_inboxes, :inboxes
    add_foreign_key :disparo_inboxes, :inboxes

    remove_column :disparo_targets, :phone_present
    add_column :disparo_targets, :phone, :string
  end
end
