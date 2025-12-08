# frozen_string_literal: true

class FazerAi::Kanban::AuditEventJob < ApplicationJob
  queue_as :low

  discard_on ActiveRecord::RecordNotFound

  # rubocop:disable Metrics/ParameterLists
  def perform(task_id:, account_id:, action:, metadata: {}, performed_by_id: nil, occurred_at: Time.current)
    account = Account.find(account_id)
    return unless account.kanban_feature_enabled?

    task = account.kanban_tasks.find(task_id)
    performed_by = performed_by_id ? account.users.find_by(id: performed_by_id) : nil

    FazerAi::Kanban::AuditLogger.log(
      task: task,
      action: action,
      metadata: metadata,
      performed_by: performed_by,
      occurred_at: occurred_at
    )
  end
  # rubocop:enable Metrics/ParameterLists
end
