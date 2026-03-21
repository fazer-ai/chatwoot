class CreateInternalChatPolls < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_polls do |t|
      t.references :internal_chat_message, null: false, foreign_key: true, index: { name: 'idx_ic_polls_message' }
      t.string :question, null: false
      t.boolean :multiple_choice, null: false, default: false
      t.boolean :public_results, null: false, default: true
      t.boolean :allow_revote, null: false, default: true
      t.datetime :expires_at
      t.timestamps
    end
    add_index :internal_chat_polls, :internal_chat_message_id, unique: true, name: 'idx_ic_polls_message_unique'
  end
end
