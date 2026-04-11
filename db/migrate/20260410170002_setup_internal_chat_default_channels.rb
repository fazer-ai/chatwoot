class SetupInternalChatDefaultChannels < ActiveRecord::Migration[7.1]
  def up
    Account.find_each do |account|
      InternalChat::DefaultChannelSetupService.new(account: account).perform
    rescue StandardError => e
      Rails.logger.error "Failed to setup internal chat for account #{account.id}: #{e.message}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Cannot safely rollback internal chat default channel setup without deleting user data'
  end
end
