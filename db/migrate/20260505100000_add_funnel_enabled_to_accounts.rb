class AddFunnelEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :funnel_enabled, :boolean, default: true, null: false
  end
end
