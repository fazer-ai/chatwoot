class AddHiddenToInternalChatChannelMembers < ActiveRecord::Migration[7.1]
  def change
    add_column :internal_chat_channel_members, :hidden, :boolean, default: false, null: false
  end
end
