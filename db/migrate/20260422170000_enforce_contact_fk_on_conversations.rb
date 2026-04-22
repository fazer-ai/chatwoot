class EnforceContactFkOnConversations < ActiveRecord::Migration[7.1]
  def up
    orphan_scope = Conversation.where(contact_id: nil).or(
      Conversation.where('NOT EXISTS (SELECT 1 FROM contacts WHERE contacts.id = conversations.contact_id)')
    )

    count = orphan_scope.count
    if count.positive?
      say "Destroying #{count} orphan conversations via Rails so dependent associations are cleaned up"
      orphan_scope.find_each(&:destroy!)
    end

    change_column_null :conversations, :contact_id, false
  end

  def down
    change_column_null :conversations, :contact_id, true
  end
end
