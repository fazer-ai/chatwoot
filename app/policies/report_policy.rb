class ReportPolicy < ApplicationPolicy
  def view?
    @account_user.administrator? || @account_user.manager?
  end
end

ReportPolicy.prepend_mod_with('ReportPolicy')
