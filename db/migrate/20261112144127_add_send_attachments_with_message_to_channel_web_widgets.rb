class AddSendAttachmentsWithMessageToChannelWebWidgets < ActiveRecord::Migration[7.2]
  def change
    add_column :channel_web_widgets, :send_attachments_with_message, :boolean, default: false, null: false
  end
end
