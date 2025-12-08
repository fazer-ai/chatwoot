# frozen_string_literal: true

class FazerAi::Kanban::BoardPolicy < FazerAi::Kanban::ApplicationPolicy
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

  def manage_agents?
    update?
  end

  def update_agents?
    update?
  end

  def manage_inboxes?
    update?
  end

  def update_inboxes?
    update?
  end

  def conversations?
    show?
  end

  def toggle_favorite?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base_policy.send(:board_scope_for, scope)
    end

    private

    def base_policy
      @base_policy ||= FazerAi::Kanban::ApplicationPolicy.new(user_context, scope)
    end
  end
end
