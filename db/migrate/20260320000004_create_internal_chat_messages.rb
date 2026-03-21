class CreateInternalChatMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_messages do |t|
      t.references :account, null: false, index: true
      t.references :internal_chat_channel, null: false, foreign_key: true
      t.bigint :sender_id, null: false
      t.text :content
      t.integer :content_type, null: false, default: 0
      t.bigint :parent_id
      t.jsonb :content_attributes, default: {}
      t.string :echo_id
      t.timestamps
    end
    add_index :internal_chat_messages, [:internal_chat_channel_id, :created_at], name: 'idx_ic_messages_channel_created'
    add_index :internal_chat_messages, [:account_id, :created_at], name: 'idx_ic_messages_account_created'
    add_index :internal_chat_messages, :parent_id
    add_index :internal_chat_messages, :sender_id
    add_foreign_key :internal_chat_messages, :users, column: :sender_id
    add_foreign_key :internal_chat_messages, :internal_chat_messages, column: :parent_id
  end
end
