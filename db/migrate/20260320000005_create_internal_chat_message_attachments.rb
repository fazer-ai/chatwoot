class CreateInternalChatMessageAttachments < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_message_attachments do |t|
      t.references :account, null: false, index: true
      t.references :internal_chat_message, null: false, foreign_key: true, index: { name: 'idx_ic_msg_attachments_message' }
      t.integer :file_type, null: false, default: 0
      t.string :external_url
      t.string :extension
      t.jsonb :meta, default: {}
      t.timestamps
    end
  end
end
