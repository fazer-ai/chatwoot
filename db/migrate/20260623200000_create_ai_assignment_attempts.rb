class CreateAiAssignmentAttempts < ActiveRecord::Migration[7.1]
  # Records one row per IA-driven team assignment so the
  # "IA → Humano" audit can answer "who was online in the target team
  # at the exact moment the IA tried to hand off?". Replaces the
  # cron-based `OnlineSnapshot` approach, which suffered from minute-
  # granularity gaps when the `:scheduled_jobs` queue lagged.
  def change
    create_table :ai_assignment_attempts do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :account_id, null: false
      t.bigint :team_id, null: false
      # nullable: when the IA only sets the team and the
      # auto-assigner cannot pick anyone (no one online in capacity),
      # `agent_assigned_id` stays NULL. That is the failed_no_online
      # case in the report.
      t.bigint :agent_assigned_id
      # The user that made the API call (the n8n credential user for
      # IA flows). Kept for traceability — the IA detection rule lives
      # in the model.
      t.bigint :triggered_by_id, null: false
      # IDs of users in the target team that were online or busy in
      # Redis at the moment of the attempt. Empty array means
      # `failed_no_online` — also the canonical failure signal.
      t.bigint :online_user_ids, array: true, default: [], null: false
      t.datetime :created_at, null: false
    end

    add_index :ai_assignment_attempts, [:account_id, :created_at]
    add_index :ai_assignment_attempts, :team_id
    add_index :ai_assignment_attempts, :agent_assigned_id
    add_index :ai_assignment_attempts, :online_user_ids, using: 'gin'
  end
end
