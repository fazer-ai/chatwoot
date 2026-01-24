# frozen_string_literal: true

class RenameKanbanBoardAutoAssignAgentSetting < ActiveRecord::Migration[7.1]
  def up
    FazerAi::Kanban::Board.find_each do |board|
      next unless board.settings.key?('auto_assign_agent_to_conversation')

      new_settings = board.settings.dup
      new_settings['sync_task_and_conversation_agents'] = new_settings.delete('auto_assign_agent_to_conversation')
      board.update_column(:settings, new_settings) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    FazerAi::Kanban::Board.find_each do |board|
      next unless board.settings.key?('sync_task_and_conversation_agents')

      new_settings = board.settings.dup
      new_settings['auto_assign_agent_to_conversation'] = new_settings.delete('sync_task_and_conversation_agents')
      board.update_column(:settings, new_settings) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
