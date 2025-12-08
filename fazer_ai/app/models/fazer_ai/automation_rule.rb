# frozen_string_literal: true

module FazerAi::AutomationRule
  def conditions_attributes
    super + %w[kanban_board_id kanban_step_id]
  end

  def actions_attributes
    super + %w[move_to_step mark_completed mark_cancelled assign_to_board]
  end
end
