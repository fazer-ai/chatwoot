class CreateFunnelStageChanges < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    create_table :funnel_stage_changes, id: :uuid, default: 'gen_random_uuid()' do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :inbox_id, null: false
      t.bigint :contact_id, null: false
      t.integer :conversation_id, null: false
      t.string :previous_stage
      t.string :new_stage, null: false
      t.integer :cycle, null: false, default: 1
      t.text :reason
      t.string :source
      t.references :user, null: true, foreign_key: { on_delete: :nullify }, index: false

      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :funnel_stage_changes, [:account_id, :conversation_id, :created_at],
              name: 'index_funnel_stage_changes_on_account_conv_created'
    add_index :funnel_stage_changes, :conversation_id
    add_index :funnel_stage_changes, :contact_id
    add_index :funnel_stage_changes, :user_id, where: 'user_id IS NOT NULL'
  end
end
