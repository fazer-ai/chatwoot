# frozen_string_literal: true

class FazerAi::Kanban::AuditLogger
  def self.log(...)
    new(...).call
  end

  def initialize(task:, action:, metadata: {}, performed_by: nil, occurred_at: nil)
    @task = task
    @action = action
    @metadata = metadata || {}
    @performed_by = performed_by
    @occurred_at = occurred_at
  end

  def call
    return unless task.account.kanban_feature_enabled?

    audit_event = build_audit_event
    if occurred_at.present?
      audit_event.created_at = occurred_at
      audit_event.updated_at = occurred_at
    end
    audit_event.save!
  end

  private

  attr_reader :task, :action, :metadata, :performed_by, :occurred_at

  def build_audit_event
    FazerAi::Kanban::AuditEvent.new(
      account: task.account,
      task: task,
      action: action,
      actor: performed_by,
      metadata: metadata
    )
  end
end
