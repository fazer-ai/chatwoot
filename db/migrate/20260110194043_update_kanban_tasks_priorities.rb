class UpdateKanbanTasksPriorities < ActiveRecord::Migration[7.1]
  def up
    FazerAi::Kanban::Task.where(priority: 'normal').update_all(priority: 'medium') # rubocop:disable Rails/SkipsModelValidations

    change_column_default :kanban_tasks, :priority, from: 'normal', to: nil
    change_column_null :kanban_tasks, :priority, true
  end

  def down
    FazerAi::Kanban::Task.where(priority: nil).update_all(priority: 'medium') # rubocop:disable Rails/SkipsModelValidations

    change_column_null :kanban_tasks, :priority, false, 'medium'
    change_column_default :kanban_tasks, :priority, from: nil, to: 'normal'

    FazerAi::Kanban::Task.where(priority: 'medium').update_all(priority: 'normal') # rubocop:disable Rails/SkipsModelValidations
  end
end
