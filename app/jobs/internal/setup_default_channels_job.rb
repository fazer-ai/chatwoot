class Internal::SetupDefaultChannelsJob < ApplicationJob
  queue_as :low

  def perform
    Account.find_each do |account|
      InternalChat::DefaultChannelSetupService.new(account: account).perform
    rescue StandardError => e
      Rails.logger.error "Failed to setup internal chat for account #{account.id}: #{e.message}"
    end
  end
end
