module Whatsapp::BaileysHandlers::MessagingHistorySet # rubocop:disable Metrics/ModuleLength
  private

  def process_messaging_history_set # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/AbcSize,Metrics/MethodLength
    provider_config = inbox.channel.provider_config

    if provider_config['sync_contacts'].presence || provider_config['sync_full_history'].presence
      contacts = params.dig(:data, :contacts) || []
      contacts.each do |contact|
        create_contact(contact) if jid_user?(contact[:id])
      rescue StandardError => e
        Rails.logger.error "Error processing contact: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    return unless provider_config['sync_full_history']

    has_created_new_message = false
    messages = params.dig(:data, :messages) || []
    messages.each do |message|
      history_handle_message(message)
      has_created_new_message = true
    rescue StandardError => e
      Rails.logger.error "Error processing message: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    inbox.channel.fetch_message_history if has_created_new_message
  end

  # TODO: Refactor jid_type method in helpers to receive the jid as an argument and use it here
  def jid_user?(jid)
    server = jid.split('@').last
    server == 's.whatsapp.net' || server == 'c.us'
  end

  # TODO: Refactor this method in helpers to receive the jid as an argument and remove it from here
  def history_phone_number_from_jid(jid)
    jid.split('@').first.split(':').first.split('_').first
  end

  def create_contact(contact)
    phone_number = history_phone_number_from_jid(contact[:id])
    name = contact[:verifiedName].presence || contact[:name].presence || phone_number
    ::ContactInboxWithContactBuilder.new(
      # FIXME: update the source_id to complete jid in future
      source_id: phone_number,
      inbox: inbox,
      contact_attributes: { name: name, phone_number: "+#{phone_number}" }
    ).perform
  end

  def history_handle_message(raw_message) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return unless raw_message[:key].present? && raw_message[:message].present? && raw_message[:messageTimestamp].present?

    jid = raw_message[:key][:remoteJid]
    return unless jid_user?(jid)

    id = raw_message[:key][:id]
    return if history_message_type(raw_message[:message]).in?(%w[protocol context unsupported])
    return if history_find_message_by_source_id(id) || history_message_under_process?(id)

    history_cache_message_source_id_in_redis(id)
    contact_inbox = find_contact_inbox(jid)

    unless contact_inbox.contact
      history_clear_message_source_id_from_redis(id)

      Rails.logger.warn "Contact not found for message: #{id}"
      return
    end

    history_create_message(raw_message, contact_inbox)
    history_clear_message_source_id_from_redis(id)
  end

  # TODO: Refactor this method in helpers to receive the raw message as an argument and remove it from here
  def history_message_type(message_content) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
    if message_content.key?(:conversation) || message_content.dig(:extendedTextMessage, :text).present?
      'text'
    elsif message_content.key?(:imageMessage)
      'image'
    elsif message_content.key?(:audioMessage)
      'audio'
    elsif message_content.key?(:videoMessage)
      'video'
    elsif message_content.key?(:documentMessage) || message_content.key?(:documentWithCaptionMessage)
      'file'
    elsif message_content.key?(:stickerMessage)
      'sticker'
    elsif message_content.key?(:reactionMessage)
      'reaction'
    elsif message_content.key?(:editedMessage)
      'edited'
    elsif message_content.key?(:protocolMessage)
      'protocol'
    elsif message_content.key?(:messageContextInfo)
      'context'
    else
      'unsupported'
    end
  end

  # TODO: Remove this method when include helpers in this module, after update the methods to receive arguments
  def history_find_message_by_source_id(source_id)
    return unless source_id

    Message.find_by(source_id: source_id).presence
  end

  def find_contact_inbox(jid)
    phone_number = history_phone_number_from_jid(jid)
    ::ContactInboxWithContactBuilder.new(
      # FIXME: update the source_id to complete jid in future
      source_id: phone_number,
      inbox: inbox,
      contact_attributes: { name: phone_number, phone_number: "+#{phone_number}" }
    ).perform
  end

  # TODO: Refactor this method in helpers to receive the source_id as an argument and remove it from here
  def history_message_under_process?(source_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: source_id)
    Redis::Alfred.get(key)
  end

  # TODO: Refactor this method in helpers to receive the source_id as an argument and remove it from here
  def history_cache_message_source_id_in_redis(source_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: source_id)
    ::Redis::Alfred.setex(key, true)
  end

  # TODO: Refactor this method in helpers to receive the source_id as an argument and remove it from here
  def history_clear_message_source_id_from_redis(source_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: source_id)
    ::Redis::Alfred.delete(key)
  end

  def history_create_message(raw_message, contact_inbox)
    conversation = get_conversation(contact_inbox)
    inbox = contact_inbox.inbox
    message = conversation.messages.build(
      content: history_message_content(raw_message),
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: raw_message[:key][:id],
      sender: history_incoming?(raw_message) ? contact_inbox.contact : inbox.account.account_users.first.user,
      sender_type: history_incoming?(raw_message) ? 'Contact' : 'User',
      message_type: history_incoming?(raw_message) ? :incoming : :outgoing,
      content_attributes: history_message_content_attributes(raw_message),
      status: process_status(raw_message[:status]) || 'sent'
    )

    message.save!
  end

  # NOTE: See reference in app/services/whatsapp/incoming_message_base_service.rb:97
  def get_conversation(contact_inbox)
    return contact_inbox.conversations.last if contact_inbox.inbox.lock_to_single_conversation

    # NOTE: if lock to single conversation is disabled, create a new conversation if previous conversation is resolved
    return contact_inbox.conversations.where.not(status: :resolved).last.presence ||
           ::Conversation.create!(conversation_params(contact_inbox))
  end

  def conversation_params(contact_inbox)
    {
      account_id: contact_inbox.inbox.account_id,
      inbox_id: contact_inbox.inbox.id,
      contact_id: contact_inbox.contact.id,
      contact_inbox_id: contact_inbox.id
    }
  end

  # TODO: Refactor this method in helpers to receive the raw message as an argument and remove it from here
  def history_incoming?(raw_message)
    !raw_message[:key][:fromMe]
  end

  # TODO: Refactor this method in helpers to receive the raw message as an argument and remove it from here
  def history_message_content(raw_message)
    raw_message.dig(:message, :conversation) ||
      raw_message.dig(:message, :extendedTextMessage, :text) ||
      raw_message.dig(:message, :imageMessage, :caption) ||
      raw_message.dig(:message, :videoMessage, :caption) ||
      raw_message.dig(:message, :documentMessage, :caption).presence ||
      raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :caption) ||
      raw_message.dig(:message, :reactionMessage, :text)
  end

  def history_message_content_attributes(raw_message)
    {
      external_created_at: baileys_extract_message_timestamp(raw_message[:messageTimestamp]),
      is_unsupported: history_message_type(raw_message[:message]).in?(%w[image file video audio sticker unsupported]) || nil
    }.compact
  end

  def process_status(status)
    {
      'PENDING' => 'sent',
      'DELIVERY_ACK' => 'delivered',
      'READ' => 'read'
    }[status]
  end
end
