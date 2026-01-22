# frozen_string_literal: true

class AddIndexKanbanTasksOnDueDate < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :kanban_tasks, :due_date, algorithm: :concurrently, name: 'index_kanban_tasks_on_due_date'
  end
end
