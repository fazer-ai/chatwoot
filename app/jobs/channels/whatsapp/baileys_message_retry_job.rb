class Channels::Whatsapp::BaileysMessageRetryJob < MutexApplicationJob
  queue_as :high

  retry_on LockAcquisitionError, wait: 3.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id, is_retry: false)
    message = Message.find(message_id)
    return unless message.conversation.inbox.channel.provider == 'baileys'

    channel_id = message.conversation.inbox.channel.id
    key = format(::Redis::Alfred::BAILEYS_MESSAGE_MUTEX, channel_id: channel_id)

    with_lock(key) do
      send_baileys_message(message, is_retry)
    end
  rescue Whatsapp::Providers::WhatsappBaileysService::MessageNotSentError => e
    handle_baileys_send_failure(message, e, is_retry)
  rescue StandardError => e
    Rails.logger.error "Unexpected error in BaileysMessageRetryJob: #{e.message}"
    handle_baileys_send_failure(message, e, is_retry)
  end

  private

  def send_baileys_message(message, is_retry)
    attempt_count = get_attempt_count(message, is_retry)

    service = Whatsapp::SendOnWhatsappService.new(message: message)
    service.perform

    message.update!(status: :sent, additional_attributes: message.additional_attributes.merge(
      baileys_retry_count: attempt_count,
      baileys_last_attempt_at: Time.current
    ))

    Rails.logger.info "Baileys message sent successfully on attempt #{attempt_count} for message #{message.id}"
  end

  def handle_baileys_send_failure(message, error, is_retry)
    attempt_count = get_attempt_count(message, is_retry)
    Rails.logger.warn "Baileys message send failed on attempt #{attempt_count} for message #{message.id}: #{error.message}"

    message.update!(
      status: :failed,
      additional_attributes: message.additional_attributes.merge(
        baileys_retry_count: attempt_count,
        baileys_last_attempt_at: Time.current,
        baileys_last_error: error.message
      )
    )

    if attempt_count >= 3
      persist_failed_message_for_redelivery(message)
    else
      retry_delay = calculate_retry_delay(attempt_count)
      self.class.set(wait: retry_delay).perform_later(message.id, is_retry: true)
    end
  end

  def get_attempt_count(message, is_retry)
    if is_retry
      (message.additional_attributes['baileys_retry_count'] || 0) + 1
    else
      1
    end
  end

  def calculate_retry_delay(attempt_count)
    base_delay = 30.seconds
    [base_delay * (2 ** (attempt_count - 1)), 5.minutes].min
  end

  def persist_failed_message_for_redelivery(message)
    failed_message_key = "baileys:failed_messages:#{message.conversation.inbox.channel.id}"
    message_data = {
      message_id: message.id,
      failed_at: Time.current.to_i,
      retry_count: message.additional_attributes['baileys_retry_count'] || 0,
      last_error: message.additional_attributes['baileys_last_error']
    }

    Redis::Alfred.rpush(failed_message_key, message_data.to_json)
    Rails.logger.info "Persisted failed Baileys message #{message.id} for future redelivery"
  end
end
