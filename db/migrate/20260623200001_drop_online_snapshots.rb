class DropOnlineSnapshots < ActiveRecord::Migration[7.1]
  # The cron-based `online_snapshots` table fed the "IA → Humano" report
  # via per-minute polling. It's been replaced by `ai_assignment_attempts`
  # (event-sourced: one row per IA-driven team assignment), which sits
  # closer to the event being audited and doesn't suffer from
  # minute-level cron gaps under Sidekiq backlog.
  def up
    drop_table :online_snapshots
  end

  def down
    create_table :online_snapshots do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.datetime :snapshot_at, null: false
      t.timestamps
    end

    add_index :online_snapshots, :account_id
    add_index :online_snapshots, %i[account_id snapshot_at]
    add_index :online_snapshots, :user_id
    add_index :online_snapshots, %i[user_id snapshot_at]
    add_foreign_key :online_snapshots, :accounts, on_delete: :cascade
    add_foreign_key :online_snapshots, :users, on_delete: :cascade
  end
end
