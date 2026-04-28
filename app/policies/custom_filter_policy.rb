class CustomFilterPolicy < ApplicationPolicy
  def create?
    @account_user.administrator? || @account_user.agent? || @account_user.manager?
  end

  def show?
    @account_user.administrator? || @account_user.agent? || @account_user.manager?
  end

  def index?
    @account_user.administrator? || @account_user.agent? || @account_user.manager?
  end

  def update?
    @account_user.administrator? || @account_user.agent? || @account_user.manager?
  end

  def destroy?
    @account_user.administrator? || @account_user.agent? || @account_user.manager?
  end
end
