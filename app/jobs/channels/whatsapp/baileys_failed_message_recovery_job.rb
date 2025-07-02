class Channels::Whatsapp::BaileysFailedMessageRecoveryJob < ApplicationJob
  queue_as :low

  def perform
    Channel::Whatsapp.where(provider: 'baileys').find_each do |channel|
      recover_failed_messages_for_channel(channel)
    end
  end

  private

  def recover_failed_messages_for_channel(channel)
    failed_message_key = "baileys:failed_messages:#{channel.id}"

    return unless baileys_api_available?(channel)

    batch_size = 10
    processed_count = 0

    while processed_count < batch_size
      message_data_json = Redis::Alfred.lpop(failed_message_key)
      break if message_data_json.nil?

      begin
        message_data = JSON.parse(message_data_json)
        message = Message.find(message_data['message_id'])

        delay = rand(1..30).seconds
        Channels::Whatsapp::BaileysMessageRetryJob.set(wait: delay).perform_later(message.id, is_retry: true)

        processed_count += 1
        Rails.logger.info "Scheduled recovery retry for Baileys message #{message.id}"

      rescue JSON::ParserError, ActiveRecord::RecordNotFound => e
        Rails.logger.error "Error processing failed message data: #{e.message}"
      end
    end

    Rails.logger.info "Processed #{processed_count} failed messages for Baileys channel #{channel.id}" if processed_count.positive?
  end

  def baileys_api_available?(channel)
    provider_service = channel.provider_service

    begin
      provider_service.validate_provider_config?
    rescue StandardError => e
      Rails.logger.debug { "Baileys API not available for channel #{channel.id}: #{e.message}" }
      false
    end
  end
end
