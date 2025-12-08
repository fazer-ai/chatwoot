# frozen_string_literal: true

class FazerAi::Kanban::BoardStepPolicy < FazerAi::Kanban::ApplicationPolicy
  def index?
    feature_enabled? && (admin? || agent?)
  end

  def create?
    feature_enabled? && admin?
  end

  def update?
    feature_enabled? && admin?
  end

  def destroy?
    update?
  end

  def reorder?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      allowed_boards = base_policy.send(:board_scope_for, FazerAi::Kanban::Board)
      scope.where(board_id: allowed_boards.select(:id))
    end

    private

    def base_policy
      @base_policy ||= FazerAi::Kanban::ApplicationPolicy.new(user_context, scope)
    end
  end
end
