# One snapshot per account per day, written by the daily job at 03:00. The
# `breakdown` JSONB carries everything Ops needs to explain the number: per
# metric sub_score + applied weight + raw values + missing reason, and the
# per-group normalized scores (Outcomes/Operational/Engagement) so the UI
# doesn't have to recompute them.
class CreateAccountHealthScores < ActiveRecord::Migration[7.1]
  def change
    create_table :account_health_scores do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.integer :score, null: false
      t.jsonb :breakdown, null: false, default: {}
      t.date :captured_on, null: false
      t.timestamps
    end

    add_index :account_health_scores, %i[account_id captured_on], unique: true
    add_index :account_health_scores, :captured_on
  end
end
