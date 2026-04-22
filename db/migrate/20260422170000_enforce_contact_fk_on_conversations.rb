class EnforceContactFkOnConversations < ActiveRecord::Migration[7.1]
  def up
    orphan_count = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM conversations
      WHERE contact_id IS NULL
         OR NOT EXISTS (SELECT 1 FROM contacts WHERE contacts.id = conversations.contact_id)
    SQL

    if orphan_count.positive?
      say "Deleting #{orphan_count} orphan conversations (contact_id NULL or pointing to missing contact)"
      execute <<~SQL.squish
        DELETE FROM conversations
        WHERE contact_id IS NULL
           OR NOT EXISTS (SELECT 1 FROM contacts WHERE contacts.id = conversations.contact_id)
      SQL
    end

    change_column_null :conversations, :contact_id, false
    add_foreign_key :conversations, :contacts, on_delete: :cascade, validate: false
    validate_foreign_key :conversations, :contacts
  end

  def down
    remove_foreign_key :conversations, :contacts
    change_column_null :conversations, :contact_id, true
  end
end
