class AccountPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || @account_user.agent? || @account_user.manager?
  end

  def cache_keys?
    @account_user.administrator? || @account_user.agent? || @account_user.manager?
  end

  def limits?
    @account_user.administrator? || @account_user.agent? || @account_user.manager?
  end

  def update?
    @account_user.administrator?
  end

  def update_active_at?
    true
  end

  def subscription?
    @account_user.administrator?
  end

  def checkout?
    @account_user.administrator?
  end

  def toggle_deletion?
    @account_user.administrator?
  end

  def topup_checkout?
    @account_user.administrator?
  end

  def enable_feature?
    @account_user.administrator?
  end
end
