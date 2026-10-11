class AddReopenAssigneeTeamToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_reference :inboxes, :reopen_assignee_team, foreign_key: { to_table: :teams, on_delete: :nullify }, index: true
  end
end
