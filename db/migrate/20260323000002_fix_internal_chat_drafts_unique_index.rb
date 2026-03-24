class FixInternalChatDraftsUniqueIndex < ActiveRecord::Migration[7.0]
  def up
    remove_index :internal_chat_drafts, name: :idx_ic_drafts_user_channel

    add_index :internal_chat_drafts, %i[user_id internal_chat_channel_id],
              unique: true, where: 'parent_id IS NULL',
              name: :idx_ic_drafts_user_channel_root
    add_index :internal_chat_drafts, %i[user_id internal_chat_channel_id parent_id],
              unique: true, where: 'parent_id IS NOT NULL',
              name: :idx_ic_drafts_user_channel_thread
  end

  def down
    remove_index :internal_chat_drafts, name: :idx_ic_drafts_user_channel_root
    remove_index :internal_chat_drafts, name: :idx_ic_drafts_user_channel_thread

    add_index :internal_chat_drafts, %i[user_id internal_chat_channel_id],
              unique: true, name: :idx_ic_drafts_user_channel
  end
end
