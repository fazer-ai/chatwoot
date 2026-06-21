class CreateOperationsNotifications < ActiveRecord::Migration[7.1]
  def change
    create_notifications_table
    create_acks_table
  end

  private

  def create_notifications_table
    create_table :operations_notifications do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.integer :severity, null: false, default: 0
      t.integer :scope_type, null: false, default: 0
      t.bigint :account_id
      t.integer :audience_type, null: false, default: 0
      t.string :audience_value
      t.integer :trigger_kind, null: false, default: 0
      t.datetime :published_at
      t.datetime :expires_at
      t.bigint :created_by_id, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    %i[account_id published_at expires_at deleted_at created_by_id].each do |col|
      add_index :operations_notifications, col
    end
  end

  def create_acks_table
    create_table :operations_notification_acks do |t|
      t.bigint :operations_notification_id, null: false
      t.bigint :user_id, null: false
      t.bigint :account_id, null: false
      t.datetime :acknowledged_at, null: false
      t.string :ip
      t.string :user_agent
      t.timestamps
    end

    add_index :operations_notification_acks,
              [:operations_notification_id, :user_id],
              unique: true,
              name: 'idx_ops_notif_acks_unique'
    add_index :operations_notification_acks, :account_id
    add_foreign_key :operations_notification_acks, :operations_notifications, on_delete: :cascade
    add_foreign_key :operations_notification_acks, :users
    add_foreign_key :operations_notification_acks, :accounts
  end
end
