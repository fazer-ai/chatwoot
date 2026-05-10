class LossReasonPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.manager? || @account_user.agent?
  end

  def show?
    index?
  end

  # LossReason is a global resource managed only from the Super Admin
  # dashboard. Account-scoped users can read but not write — preventing a
  # single tenant from mutating a record that the rest of the install relies on.
  def create?
    false
  end

  def update?
    false
  end
end
