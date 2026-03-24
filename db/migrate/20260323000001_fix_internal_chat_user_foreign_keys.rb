class FixInternalChatUserForeignKeys < ActiveRecord::Migration[7.0]
  def up
    # Messages: preserve messages but nullify sender on user deletion
    remove_foreign_key :internal_chat_messages, column: :sender_id
    change_column_null :internal_chat_messages, :sender_id, true
    add_foreign_key :internal_chat_messages, :users, column: :sender_id, on_delete: :nullify

    # Reactions: cascade delete when user is deleted
    remove_foreign_key :internal_chat_reactions, :users
    add_foreign_key :internal_chat_reactions, :users, on_delete: :cascade

    # Poll votes: cascade delete when user is deleted
    remove_foreign_key :internal_chat_poll_votes, :users
    add_foreign_key :internal_chat_poll_votes, :users, on_delete: :cascade

    # Channel members: cascade delete when user is deleted
    remove_foreign_key :internal_chat_channel_members, :users
    add_foreign_key :internal_chat_channel_members, :users, on_delete: :cascade
  end

  def down
    remove_foreign_key :internal_chat_messages, column: :sender_id
    change_column_null :internal_chat_messages, :sender_id, false
    add_foreign_key :internal_chat_messages, :users, column: :sender_id

    remove_foreign_key :internal_chat_reactions, :users
    add_foreign_key :internal_chat_reactions, :users

    remove_foreign_key :internal_chat_poll_votes, :users
    add_foreign_key :internal_chat_poll_votes, :users

    remove_foreign_key :internal_chat_channel_members, :users
    add_foreign_key :internal_chat_channel_members, :users
  end
end
