class SetupInternalChatDefaultChannels < ActiveRecord::Migration[7.0]
  def up
    Account.find_each do |account|
      InternalChat::DefaultChannelSetupService.new(account: account).perform
    rescue StandardError => e
      Rails.logger.error "Failed to setup internal chat for account #{account.id}: #{e.message}"
    end
  end

  def down
    InternalChat::Category.destroy_all
  end
end
