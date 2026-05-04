class AddAverageTicketToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :average_ticket, :decimal, precision: 12, scale: 2
  end
end
