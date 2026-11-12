class AddImageOptionsToChannelWebWidgets < ActiveRecord::Migration[7.2]
  def change
    change_table :channel_web_widgets, bulk: true do |t|
      t.boolean :attachment_editor_enabled, default: true, null: false
      t.boolean :screen_capture_enabled, default: false, null: false
      t.boolean :screen_capture_editor_enabled, default: true, null: false
    end
  end
end
