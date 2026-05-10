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
    return @account_user.administrator? if @record.global?

    author?
  end

  def destroy?
    return @account_user.administrator? if @record.global?

    author?
  end

  private

  def author?
    @record.user == @account_user.user
  end
end
