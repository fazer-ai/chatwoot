class CreateInternalChatPollOptions < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_poll_options do |t|
      t.references :internal_chat_poll, null: false, foreign_key: true, index: { name: 'idx_ic_poll_options_poll' }
      t.string :text, null: false
      t.string :emoji
      t.string :image_url
      t.integer :position, null: false, default: 0
      t.datetime :created_at, null: false
    end
    add_index :internal_chat_poll_options, [:internal_chat_poll_id, :position], name: 'idx_ic_poll_options_poll_pos'
  end
end
