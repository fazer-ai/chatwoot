class SeedFunnelStagesForExistingAccounts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    return unless defined?(Funnel::DefaultStagesSeederService)

    Account.find_each(batch_size: 100) do |account|
      Funnel::DefaultStagesSeederService.new(account: account).perform
    rescue StandardError => e
      Rails.logger.error("Failed to seed funnel stages for account #{account.id}: #{e.message}")
    end
  end

  def down
    # Removing previously seeded stages would risk data loss for accounts that
    # already moved conversations through them. Leaving as a no-op on purpose.
  end
end
