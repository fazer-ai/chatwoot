class AddOverdueNotifiedAtToKanbanTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_tasks, :overdue_notified_at, :datetime
  end
end
