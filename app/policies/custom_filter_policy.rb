class CustomFilterPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @record.global? || author?
  end

  def update?
    author? || (@account_user.administrator? && @record.global?)
  end

  def destroy?
    author? || (@account_user.administrator? && @record.global?)
  end

  private

  def author?
    @record.user == @account_user.user
  end
end
