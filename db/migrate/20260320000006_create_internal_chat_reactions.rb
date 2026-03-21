class CreateInternalChatReactions < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_reactions do |t|
      t.references :internal_chat_message, null: false, foreign_key: true, index: { name: 'idx_ic_reactions_message' }
      t.references :user, null: false, foreign_key: true
      t.string :emoji, null: false
      t.datetime :created_at, null: false
    end
    add_index :internal_chat_reactions, [:internal_chat_message_id, :user_id, :emoji],
              unique: true, name: 'idx_ic_reactions_message_user_emoji'
  end
end
