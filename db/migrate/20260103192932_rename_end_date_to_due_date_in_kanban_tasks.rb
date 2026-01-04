class RenameEndDateToDueDateInKanbanTasks < ActiveRecord::Migration[7.1]
  def change
    rename_column :kanban_tasks, :end_date, :due_date
  end
end
