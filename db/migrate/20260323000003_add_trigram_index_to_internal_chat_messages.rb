class AddTrigramIndexToInternalChatMessages < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :internal_chat_messages, :content,
              name: 'idx_ic_messages_content_trgm',
              using: :gin,
              opclass: :gin_trgm_ops,
              algorithm: :concurrently
  end
end
