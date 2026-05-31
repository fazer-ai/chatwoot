class DropWf15BaselineTables < ActiveRecord::Migration[7.1]
  # wf15 parity was dropped from scope. These tables (and their parity machinery)
  # are no longer referenced by any surviving code. Reversible drop: `up` removes
  # the tables (FK child first); `down` recreates them with their current columns,
  # indexes and the rows->runs cascade FK (mirrors create_wf15_baseline_tables +
  # add_diagnostic_to_wf15_baseline_runs). A bare drop_table in `change` would
  # raise IrreversibleMigration, so up/down are explicit.
  def up
    drop_table :wf15_baseline_rows
    drop_table :wf15_baseline_runs
  end

  def down # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :wf15_baseline_runs do |t|
      t.string :baseline_run_id, null: false
      t.column :exported_at, :timestamptz
      t.string :source_snapshot_id, null: false
      t.column :prod_snapshot_at, :timestamptz, null: false
      t.column :run_started_at, :timestamptz, null: false
      t.column :run_completed_at, :timestamptz, null: false
      t.string :filter_digest, null: false
      t.string :template_name, null: false
      t.timestamps
      t.boolean :diagnostic, null: false, default: false
      t.index :baseline_run_id, unique: true
    end

    create_table :wf15_baseline_rows do |t|
      t.references :wf15_baseline_run, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :conversation_id, null: false
      t.integer :contact_id, null: false
      t.string :wf15_decision, null: false
      t.string :delivery_result, null: false
      t.string :primary_skip_reason
      t.jsonb :skip_reasons, null: false, default: []
      t.boolean :phone_present, null: false, default: false
      t.boolean :phone_valid, null: false, default: false
      t.string :phone_e164_hmac
      t.column :window_closes_at, :timestamptz
      t.column :template_last_sent_at, :timestamptz
      t.integer :estimated_cost_usd_cents
      t.string :source_workflow_id
      t.string :source_execution_id
      t.timestamps
      t.index [:wf15_baseline_run_id, :conversation_id, :contact_id], unique: true
    end
  end
end
