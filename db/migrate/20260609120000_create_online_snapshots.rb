# Captures who was 'online' in each account at one-minute granularity. Used
# by the IA → Humano report to answer "who was online at the exact moment
# the IA tried to auto-assign a conversation?". Only 'online' users land
# in the table; offline/busy are implicit (absent). The capture job rolls
# 7 days; older rows are deleted by the same job.
class CreateOnlineSnapshots < ActiveRecord::Migration[7.1]
  def change
    # rubocop:disable Rails/CreateTableWithTimestamps
    # Only snapshot_at matters here; the table is high-write with a 7d
    # rolling retention so created_at/updated_at would just be bloat.
    create_table :online_snapshots do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :snapshot_at, null: false
    end
    # rubocop:enable Rails/CreateTableWithTimestamps

    add_index :online_snapshots, %i[account_id snapshot_at]
    add_index :online_snapshots, %i[user_id snapshot_at]
  end
end
