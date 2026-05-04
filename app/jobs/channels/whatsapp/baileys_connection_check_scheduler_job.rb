class Channels::Whatsapp::BaileysConnectionCheckSchedulerJob < ApplicationJob
  queue_as :low

  def perform
    Channel::Whatsapp.with_reconnection_enabled
                     .where(provider: 'baileys')
                     .where("provider_connection->>'connection' = ?", 'open')
                     .find_each do |channel|
      Channels::Whatsapp::BaileysConnectionCheckJob.perform_later(channel)
    end
  end
end
