class TeamMemberPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    @account_user.administrator? || @account_user.manager?
  end

  def destroy?
    @account_user.administrator? || @account_user.manager?
  end

  def update?
    @account_user.administrator? || @account_user.manager?
  end
end
