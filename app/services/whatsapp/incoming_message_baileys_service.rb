class Whatsapp::IncomingMessageBaileysService < Whatsapp::IncomingMessageBaseService
  class InvalidWebhookVerifyToken < StandardError; end

  def perform
    processed_params

    raise InvalidWebhookVerifyToken if processed_params[:webhookVerifyToken] != inbox.channel.provider_config['webhook_verify_token']
    return if processed_params[:event].blank? || processed_params[:data].blank?

    event_prefix = processed_params[:event].gsub(/[\.-]/, '_')
    method_name = "process_#{event_prefix}"
    if respond_to?(method_name, true)
      send(method_name)
    else
      Rails.logger.warn "Baileys unsupported event: #{processed_params[:event]}"
    end
  end

  private

  def process_connection_update
    data = processed_params[:data]

    inbox.channel.update!(
      provider_connection: {
        connection: data[:connection] || inbox.channel.provider_connection['connection'],
        qr_data_url: data[:qrDataUrl],
        error: data[:error]
      }.compact
    )
    # FIXME: Race condition on account cache if multiple connection updates are sent close together
    inbox.update_account_cache

    Rails.logger.error "Baileys connection error: #{data[:error]}" if data[:error].present?
  end

  def process_credentials_update; end
  def process_messaging_history; end
  def process_chats; end
  def process_presence; end
  def process_contacts; end
  def process_message_receipt; end
  def process_groups; end
  def process_blocklist; end
  def process_call; end
  def process_group_participants; end
  def process_label; end

  def process_messages_upsert
    messages = processed_params[:data][:messages]
    messages.each do |message|
      @raw_message = message
      if processed_params[:data][:type] == 'notify'
        process_notify_message
      elsif processed_params[:data][:type] == 'append'
        process_append_message
      end
    end
  end

  def process_notify_message
    return if find_message_by_source_id(message_id) || message_under_process?

    cache_message_source_id_in_redis
    set_contact
    return unless @contact

    set_conversation
    handle_message
    clear_message_source_id_from_redis
  end

  def process_append_message
    raise 'Not implemented'
  end

  def handle_message
    case message_type
    when 'text'
      create_regular_message
    else
      Rails.logger.warn "Baileys unsupported message type: #{message_type}"
    end
  end

  def create_regular_message
    create_message
    @message.save!
  end

  def create_message
    @message = @conversation.messages.build(
      content: message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: message_id.to_s,
      in_reply_to_external_id: nil
    )
  end

  def message_content
    @raw_message[:message][:conversation]
  end

  def message_id
    @raw_message[:key][:id]
  end

  def message_type # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    message = @raw_message[:message]
    return 'text' if message.key?(:conversation)
    return 'contacts' if message.key?(:contactMessage)
    return 'image' if message.key?(:imageMessage)
    return 'audio' if message.key?(:audioMessage)
    return 'video' if message.key?(:videoMessage)
    return 'video_note' if message.key?(:ptvMessage)
    return 'location' if message.key?(:locationMessage)
    return 'live_location' if message.key?(:liveLocationMessage)
    return 'document' if message.key?(:documentMessage)
    return 'poll' if message.key?(:pollCreationMessageV3)
    return 'event' if message.key?(:eventMessage)
    return 'sticker' if message.key?(:stickerMessage)

    'unsupported'
  end

  def set_contact
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: phone_number_from_jid,
      inbox: inbox,
      contact_attributes: { name: @raw_message[:pushName], phone_number: "+#{phone_number_from_jid}" }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
  end

  def phone_number_from_jid
    @phone_number_from_jid ||= @raw_message[:key][:remoteJid].split('@')[0].split(':')[0]
  end

  def message_under_process?
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    Redis::Alfred.get(key)
  end

  def cache_message_source_id_in_redis
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    ::Redis::Alfred.setex(key, true)
  end

  def clear_message_source_id_from_redis
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
    ::Redis::Alfred.delete(key)
  end
end
