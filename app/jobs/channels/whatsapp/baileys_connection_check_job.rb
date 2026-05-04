class Channels::Whatsapp::BaileysConnectionCheckJob < ApplicationJob
  queue_as :low

  def perform(whatsapp_channel)
    return unless whatsapp_channel.reconnection_enabled?

    whatsapp_channel.setup_channel_provider
  end
end
