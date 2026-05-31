class DisparoPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def dry_run?
    @account_user.administrator?
  end

  def shadow_run?
    @account_user.administrator?
  end

  def targets?
    @account_user.administrator?
  end
end
