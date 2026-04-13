class Conversations::PresenceSubscribeService
  def initialize(account, conversation_ids)
    @account = account
    @conversation_ids = Array(conversation_ids).first(10)
  end

  def perform
    return if @conversation_ids.blank?

    jids_by_channel = collect_jids
    jids_by_channel.each do |channel, jids|
      channel.presence_subscribe(jids)
    rescue StandardError => e
      Rails.logger.error "PresenceSubscribeService: failed for channel #{channel.id}: #{e.message}"
    end
  end

  private

  def collect_jids
    conversations = @account.conversations
                            .where(display_id: @conversation_ids)
                            .includes(inbox: :channel, contact: [])
    result = {}
    conversations.each do |conv|
      channel = conv.inbox.channel
      next unless channel.is_a?(Channel::Whatsapp) && channel.provider_config&.dig('presence_subscribe')

      jid = contact_jid(conv.contact)
      next if jid.blank?

      (result[channel] ||= []) << jid
    end
    result
  end

  def contact_jid(contact)
    contact.identifier.presence || phone_jid(contact.phone_number)
  end

  def phone_jid(phone_number)
    return if phone_number.blank?

    "#{phone_number.delete('+')}@s.whatsapp.net"
  end
end
