class CreateDisparosTables < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :disparos do |t|
      t.references :account, type: :integer, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.integer :mode, null: false, default: 0
      t.jsonb :audience_filter, null: false, default: {}
      t.integer :audience_filter_dsl_version, null: false, default: 1
      t.integer :created_by_id
      t.timestamps
      t.index [:account_id, :status]
    end
    add_foreign_key :disparos, :users, column: :created_by_id

    create_table :disparo_inboxes do |t|
      t.references :disparo, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :inbox, type: :integer, null: false, foreign_key: true
      t.integer :provider, null: false, default: 0
      t.timestamps
      t.index [:disparo_id, :inbox_id], unique: true
    end

    create_table :disparo_targets do |t|
      t.references :disparo, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :conversation_id, null: false
      t.integer :contact_id, null: false
      t.integer :inbox_id
      t.string :phone
      t.integer :state, null: false, default: 0
      t.string :primary_skip_reason
      t.string :skip_reasons, null: false, default: [], array: true
      t.boolean :shadow_run, null: false, default: false
      t.uuid :dispatch_id, null: false, default: -> { 'gen_random_uuid()' }
      t.timestamps
      t.index [:disparo_id, :conversation_id, :contact_id], unique: true
      t.index [:disparo_id, :state]
      t.index :dispatch_id, unique: true
    end

    create_table :disparo_events do |t|
      t.references :disparo_target, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.integer :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false
      t.index :event_type
    end

    create_table :disparo_audience_snapshots do |t|
      t.references :disparo, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.jsonb :filter_dsl, null: false, default: {}
      t.integer :inbox_ids, null: false, default: [], array: true
      t.integer :total_eligible, null: false, default: 0
      t.jsonb :by_skip_reason, null: false, default: {}
      t.jsonb :by_inbox, null: false, default: {}
      t.integer :estimated_cost_cents
      t.datetime :expires_at
      t.timestamps
    end
  end
end
