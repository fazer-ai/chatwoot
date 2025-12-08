# frozen_string_literal: true

module FazerAi::ActivityMessageHandler
  def automation_status_change_activity_content
    if Current.executed_by.instance_of?(FazerAi::Kanban::TaskAutomation)
      kanban_task_status_change_activity_content
    else
      super
    end
  end

  private

  def kanban_task_status_change_activity_content
    return unless resolved?

    task = Current.executed_by.task
    I18n.t(
      'conversations.activity.status.kanban_task_resolved',
      task_title: task.title,
      board_name: task.board.name
    )
  end
end
