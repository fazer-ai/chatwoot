# frozen_string_literal: true

class FazerAi::Kanban::AuditEventPolicy < FazerAi::Kanban::ApplicationPolicy
  def index?
    feature_enabled? && (admin? || agent?)
  end

  def show?
    feature_enabled? && accessible_task?(record&.task)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      task_scope = base_policy.send(:task_scope_for, FazerAi::Kanban::Task)

      scope.joins(:task).where(kanban_tasks: { id: task_scope.select(:id) })
    end

    private

    def base_policy
      @base_policy ||= FazerAi::Kanban::ApplicationPolicy.new(user_context, scope)
    end
  end
end
