class CreateInternalChatDrafts < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_drafts do |t|
      t.references :account, null: false, index: true
      t.references :user, null: false, foreign_key: true
      t.references :internal_chat_channel, null: false, foreign_key: true, index: { name: 'idx_ic_drafts_channel' }
      t.text :content, null: false
      t.bigint :parent_id
      t.timestamps
    end
    add_index :internal_chat_drafts, [:user_id, :internal_chat_channel_id], unique: true, name: 'idx_ic_drafts_user_channel'
    add_index :internal_chat_drafts, [:user_id, :updated_at], name: 'idx_ic_drafts_user_updated'
  end
end
