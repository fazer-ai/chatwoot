class Whatsapp::BaileysRetryMonitorService
  def self.failed_message_stats
    stats = {}

    Channel::Whatsapp.where(provider: 'baileys').find_each do |channel|
      failed_message_key = "baileys:failed_messages:#{channel.id}"
      failed_count = Redis::Alfred.llen(failed_message_key)

      if failed_count.positive?
        stats[channel.id] = {
          channel_phone: channel.phone_number,
          failed_messages_count: failed_count,
          oldest_failed_message: get_oldest_failed_message(failed_message_key)
        }
      end
    end

    stats
  end

  def self.retry_statistics
    messages_with_retries = Message.joins(:conversation)
                                   .joins('JOIN inboxes ON conversations.inbox_id = inboxes.id')
                                   .joins('JOIN channel_whatsapp ON inboxes.channel_id = channel_whatsapp.id')
                                   .where("channel_whatsapp.provider = 'baileys'")
                                   .where("messages.additional_attributes ? 'baileys_retry_count'")
                                   .where('messages.created_at > ?', 24.hours.ago)

    {
      total_messages_with_retries: messages_with_retries.count,
      average_retry_count: messages_with_retries.average("(additional_attributes->>'baileys_retry_count')::int"),
      failed_after_all_retries: messages_with_retries.where(status: :failed).count
    }
  end

  def self.get_oldest_failed_message(key)
    oldest_json = Redis::Alfred.lrange(key, 0, 0).first
    return nil unless oldest_json

    JSON.parse(oldest_json)['failed_at']
  rescue JSON::ParserError
    nil
  end
end
