class AddStepChangedAtToKanbanTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_tasks, :step_changed_at, :datetime
  end
end
