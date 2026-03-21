class CreateInternalChatPollVotes < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_poll_votes do |t|
      t.references :internal_chat_poll_option, null: false, foreign_key: true, index: { name: 'idx_ic_poll_votes_option' }
      t.references :user, null: false, foreign_key: true
      t.datetime :created_at, null: false
    end
    add_index :internal_chat_poll_votes, [:internal_chat_poll_option_id, :user_id], unique: true, name: 'idx_ic_poll_votes_option_user'
  end
end
