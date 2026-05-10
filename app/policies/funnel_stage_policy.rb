class FunnelStagePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.manager? || @account_user.agent?
  end

  def show?
    index?
  end

  # FunnelStage is a global resource managed only from the Super Admin
  # dashboard. Account-scoped users (admin, manager, agent) can read but
  # never write — preventing one account from mutating a record that other
  # accounts depend on.
  def create?
    false
  end

  def update?
    false
  end

  def destroy?
    false
  end
end
