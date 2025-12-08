# frozen_string_literal: true

class FazerAi::Kanban::BoardInboxPolicy < FazerAi::Kanban::ApplicationPolicy
  def index?
    admin_with_feature?
  end

  def create?
    admin_with_feature?
  end

  def destroy?
    admin_with_feature?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless admin_with_feature?

      scope.joins(:board).where(FazerAi::Kanban::Board.table_name => { account_id: account.id })
    end

    private

    def admin_with_feature?
      account&.kanban_feature_enabled? && account_user&.administrator?
    end
  end

  private

  def admin_with_feature?
    feature_enabled? && admin?
  end
end
