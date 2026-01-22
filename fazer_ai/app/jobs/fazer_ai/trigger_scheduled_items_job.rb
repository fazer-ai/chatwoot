# frozen_string_literal: true

module FazerAi::TriggerScheduledItemsJob
  def perform
    super

    ## Triggers FazerAi specific jobs
    ####################################

    # Triggers webhook notifications for due kanban tasks
    # Tasks due within last 5 minutes (matching schedule interval)
    # Excludes cancelled tasks at DB level, completed status checked in individual job
    FazerAi::Kanban::Task
      .joins(:board_step)
      .where.not(kanban_board_steps: { cancelled: true })
      .where(due_date: 5.minutes.ago..Time.current)
      .find_each do |task|
        FazerAi::Kanban::TriggerTaskDueWebhookJob.perform_later(task)
      end
  end
end
