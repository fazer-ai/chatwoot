# Flip the funnel feature off by default. Newly created accounts and the rows
# that came in via 20260505100000_add_funnel_enabled_to_accounts (which set
# default: true) all get reset to false. Super admins re-enable per account
# from /super_admin/accounts/:id/edit.
class DisableFunnelForAllAccountsByDefault < ActiveRecord::Migration[7.1]
  def up
    change_column_default :accounts, :funnel_enabled, from: true, to: false
    Account.in_batches.update_all(funnel_enabled: false) # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    change_column_default :accounts, :funnel_enabled, from: false, to: true
    Account.in_batches.update_all(funnel_enabled: true) # rubocop:disable Rails/SkipsModelValidations
  end
end
