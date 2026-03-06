# frozen_string_literal: true

class FazerAi::Kanban::TriggerTaskDueWebhooksSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    FazerAi::Kanban::Task
      .joins(:board_step)
      .where.not(kanban_board_steps: { cancelled: true })
      .where(due_date: 10.minutes.ago..Time.current)
      .where(overdue_notified_at: nil)
      .find_each do |task|
        # Atomically claim to prevent duplicate enqueues from concurrent scheduler runs.
        claimed = FazerAi::Kanban::Task.where(id: task.id, overdue_notified_at: nil)
                                       .update_all(overdue_notified_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        next unless claimed == 1

        begin
          FazerAi::Kanban::TriggerTaskDueWebhookJob.perform_later(task)
        rescue StandardError
          # Reset so the next scheduler run can re-claim and retry the enqueue.
          FazerAi::Kanban::Task.where(id: task.id)
                               .update_all(overdue_notified_at: nil) # rubocop:disable Rails/SkipsModelValidations
        end
      end
  end
end
