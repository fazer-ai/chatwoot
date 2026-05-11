class ChangeInboxLockToSingleConversationDefaultToTrue < ActiveRecord::Migration[7.1]
  # Auris standard: new inboxes default to "reopen the same conversation"
  # rather than spawning a fresh conversation for every incoming message.
  # Only the column default changes — existing inboxes keep whatever value
  # they currently have set.
  def up
    change_column_default :inboxes, :lock_to_single_conversation, true
  end

  def down
    change_column_default :inboxes, :lock_to_single_conversation, false
  end
end
