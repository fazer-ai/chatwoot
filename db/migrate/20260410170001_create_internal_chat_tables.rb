class CreateInternalChatTables < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :internal_chat_categories do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [:account_id, :name], unique: true
      t.index [:account_id, :position]
    end

    create_table :internal_chat_channels do |t|
      t.references :account, null: false, index: true
      t.references :category, null: true, foreign_key: { to_table: :internal_chat_categories }
      t.string :name
      t.text :description
      t.integer :channel_type, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.bigint :created_by_id
      t.datetime :last_activity_at, null: false
      t.integer :messages_count, default: 0
      t.uuid :uuid, null: false, default: -> { 'gen_random_uuid()' }
      t.timestamps
      t.index [:account_id, :channel_type]
      t.index [:account_id, :category_id]
      t.index [:account_id, :status]
      t.index :uuid, unique: true
    end
    add_foreign_key :internal_chat_channels, :users, column: :created_by_id

    create_table :internal_chat_channel_members do |t|
      t.references :internal_chat_channel, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :role, null: false, default: 0
      t.boolean :muted, null: false, default: false
      t.datetime :last_read_at
      t.boolean :favorited, null: false, default: false
      t.boolean :hidden, null: false, default: false
      t.timestamps
      t.index [:internal_chat_channel_id, :user_id], unique: true, name: 'idx_ic_channel_members_channel_user'
      t.index [:user_id, :favorited], name: 'idx_ic_channel_members_user_favorited'
    end

    create_table :internal_chat_channel_teams do |t|
      t.references :internal_chat_channel, null: false, foreign_key: true, index: false
      t.references :team, null: false, foreign_key: true
      t.timestamps
      t.index [:internal_chat_channel_id, :team_id], unique: true, name: 'idx_ic_channel_teams_channel_team'
    end

    create_table :internal_chat_messages do |t|
      t.references :account, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.references :internal_chat_channel, null: false, foreign_key: true
      t.bigint :sender_id
      t.text :content
      t.integer :content_type, null: false, default: 0
      t.bigint :parent_id
      t.integer :replies_count, null: false, default: 0
      t.jsonb :content_attributes, default: {}
      t.string :echo_id
      t.timestamps
      t.index [:internal_chat_channel_id, :created_at], name: 'idx_ic_messages_channel_created'
      t.index [:account_id, :created_at], name: 'idx_ic_messages_account_created'
      t.index :parent_id
      t.index :sender_id
    end
    add_foreign_key :internal_chat_messages, :users, column: :sender_id, on_delete: :nullify
    add_foreign_key :internal_chat_messages, :internal_chat_messages, column: :parent_id

    create_table :internal_chat_message_attachments do |t|
      t.references :account, null: false, index: true
      t.references :internal_chat_message, null: false, foreign_key: true, index: { name: 'idx_ic_msg_attachments_message' }
      t.integer :file_type, null: false, default: 0
      t.string :external_url
      t.string :extension
      t.jsonb :meta, default: {}
      t.timestamps
    end

    create_table :internal_chat_reactions do |t|
      t.references :internal_chat_message, null: false, foreign_key: true, index: { name: 'idx_ic_reactions_message' }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :emoji, null: false
      t.datetime :created_at, null: false
      t.index [:internal_chat_message_id, :user_id, :emoji], unique: true, name: 'idx_ic_reactions_message_user_emoji'
    end

    create_table :internal_chat_polls do |t|
      t.references :internal_chat_message, null: false, foreign_key: true, index: { name: 'idx_ic_polls_message' }
      t.string :question, null: false
      t.boolean :multiple_choice, null: false, default: false
      t.boolean :public_results, null: false, default: true
      t.boolean :allow_revote, null: false, default: true
      t.datetime :expires_at
      t.timestamps
      t.index :internal_chat_message_id, unique: true, name: 'idx_ic_polls_message_unique'
    end

    create_table :internal_chat_poll_options do |t|
      t.references :internal_chat_poll, null: false, foreign_key: true, index: { name: 'idx_ic_poll_options_poll' }
      t.string :text, null: false
      t.string :emoji
      t.string :image_url
      t.integer :position, null: false, default: 0
      t.integer :votes_count, null: false, default: 0
      t.datetime :created_at, null: false
      t.index [:internal_chat_poll_id, :position], name: 'idx_ic_poll_options_poll_pos'
    end

    create_table :internal_chat_poll_votes do |t|
      t.references :internal_chat_poll_option, null: false, foreign_key: true, index: { name: 'idx_ic_poll_votes_option' }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :created_at, null: false
      t.index [:internal_chat_poll_option_id, :user_id], unique: true, name: 'idx_ic_poll_votes_option_user'
    end

    create_table :internal_chat_drafts do |t|
      t.references :account, null: false, index: true
      t.references :user, null: false, foreign_key: true
      t.references :internal_chat_channel, null: false, foreign_key: true, index: { name: 'idx_ic_drafts_channel' }
      t.text :content, null: false
      t.bigint :parent_id
      t.timestamps
      t.index [:user_id, :internal_chat_channel_id],
              unique: true, where: 'parent_id IS NULL', name: 'idx_ic_drafts_user_channel_root'
      t.index [:user_id, :internal_chat_channel_id, :parent_id],
              unique: true, where: 'parent_id IS NOT NULL', name: 'idx_ic_drafts_user_channel_thread'
      t.index [:user_id, :updated_at], name: 'idx_ic_drafts_user_updated'
    end
  end
end
