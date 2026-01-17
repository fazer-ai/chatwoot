class AddIndexKanbanTasksOnStepAndCreatedAt < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :kanban_tasks, [:board_step_id, :created_at],
              name: 'index_kanban_tasks_on_step_and_created_at',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
