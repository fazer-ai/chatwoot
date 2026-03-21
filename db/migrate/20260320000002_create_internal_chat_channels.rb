class CreateInternalChatChannels < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_channels do |t|
      t.references :account, null: false, index: true
      t.references :category, null: true, foreign_key: { to_table: :internal_chat_categories }
      t.string :name
      t.text :description
      t.integer :channel_type, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.bigint :created_by_id
      t.datetime :last_activity_at, null: false
      t.integer :messages_count, default: 0
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.timestamps
    end
    add_index :internal_chat_channels, [:account_id, :channel_type]
    add_index :internal_chat_channels, [:account_id, :category_id]
    add_index :internal_chat_channels, [:account_id, :status]
    add_index :internal_chat_channels, :uuid, unique: true
    add_foreign_key :internal_chat_channels, :users, column: :created_by_id
  end
end
