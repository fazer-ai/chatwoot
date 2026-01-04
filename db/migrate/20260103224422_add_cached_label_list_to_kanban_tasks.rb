# frozen_string_literal: true

class AddCachedLabelListToKanbanTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_tasks, :cached_label_list, :text
  end
end
