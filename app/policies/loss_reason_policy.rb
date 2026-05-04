class LossReasonPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.manager? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    @account_user.administrator? || @account_user.manager?
  end

  def update?
    create?
  end
end
