class RedesignOperationsNotificationsTargeting < ActiveRecord::Migration[7.1]
  # The original schema modelled targeting with a single `account_id` plus a
  # free-form `audience_value` string. The super-admin form now lets the
  # operator pick *multiple* accounts and, when targeting specific users,
  # *multiple* users. To keep the read path cheap we store both as native
  # `bigint[]` columns (GIN-indexed for membership lookups) instead of
  # introducing join tables. The feature has not shipped to production yet,
  # so we just discard any local rows rather than back-fill them.
  def up
    execute <<~SQL.squish
      TRUNCATE TABLE operations_notification_acks, operations_notifications RESTART IDENTITY CASCADE
    SQL

    remove_index :operations_notifications, :account_id if index_exists?(:operations_notifications, :account_id)
    remove_column :operations_notifications, :account_id, :bigint
    remove_column :operations_notifications, :audience_value, :string

    add_column :operations_notifications, :account_ids, :bigint, array: true, default: [], null: false
    add_column :operations_notifications, :audience_user_ids, :bigint, array: true, default: [], null: false

    add_index :operations_notifications, :account_ids, using: 'gin'
    add_index :operations_notifications, :audience_user_ids, using: 'gin'
  end

  def down
    remove_index :operations_notifications, :account_ids if index_exists?(:operations_notifications, :account_ids)
    remove_index :operations_notifications, :audience_user_ids if index_exists?(:operations_notifications, :audience_user_ids)

    remove_column :operations_notifications, :account_ids, :bigint, array: true, default: []
    remove_column :operations_notifications, :audience_user_ids, :bigint, array: true, default: []

    add_column :operations_notifications, :account_id, :bigint
    add_column :operations_notifications, :audience_value, :string
    add_index :operations_notifications, :account_id
  end
end
