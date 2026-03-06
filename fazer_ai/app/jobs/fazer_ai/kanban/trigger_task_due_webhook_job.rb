# frozen_string_literal: true

# Processes webhook notifications for a single task that has become due.
# Called by TriggerTaskDueWebhooksSchedulerJob.
# Similar to Campaigns::TriggerOneoffCampaignJob pattern.
class FazerAi::Kanban::TriggerTaskDueWebhookJob < ApplicationJob
  queue_as :medium

  def perform(task)
    return unless task.status == 'open'
    return unless task.overdue?

    payload = task.push_event_data.merge(event: 'kanban_task_overdue')

    task.account.webhooks.account_type.each do |webhook|
      next unless webhook.subscriptions.include?('kanban_task_overdue')

      WebhookJob.perform_later(webhook.url, payload)
    end
  end
end
