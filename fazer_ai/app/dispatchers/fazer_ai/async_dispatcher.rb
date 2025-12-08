# frozen_string_literal: true

module FazerAi::AsyncDispatcher
  def listeners
    super + [
      FazerAi::KanbanListener.instance,
      FazerAi::KanbanAutomationRuleListener.instance
    ]
  end
end
