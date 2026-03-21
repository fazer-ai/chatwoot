class CreateInternalChatChannelMembers < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_channel_members do |t|
      t.references :internal_chat_channel, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.boolean :muted, null: false, default: false
      t.datetime :last_read_at
      t.boolean :favorited, null: false, default: false
      t.timestamps
    end
    add_index :internal_chat_channel_members, [:internal_chat_channel_id, :user_id],
              unique: true, name: 'idx_ic_channel_members_channel_user'
    add_index :internal_chat_channel_members, [:user_id, :favorited], name: 'idx_ic_channel_members_user_favorited'
  end
end
