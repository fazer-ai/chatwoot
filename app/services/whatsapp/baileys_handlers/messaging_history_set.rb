module Whatsapp::BaileysHandlers::MessagingHistorySet # rubocop:disable Metrics/ModuleLength
  # include Whatsapp::BaileysHandlers::Helpers
  # include BaileysHelper

  private

  def process_messaging_history_set
    contacts = params.dig(:data, :contacts) || []
    contacts.each do |contact|
      create_contact(contact) if jid_user?(contact[:id])
    end

    messages = params.dig(:data, :messages) || []
    messages.each do |message|
      handle_message(message)
    end
  end

  # TODO: Refactor jid_type method in helpers to receive the jid as an argument and use it here
  def jid_user?(jid)
    server = jid.split('@').last
    server == 's.whatsapp.net' || server == 'c.us'
  end

  # TODO: Refactor this method in helpers to receive the jid as an argument and remove it from here
  def phone_number_from_jid(jid)
    jid.split('@').first.split(':').first.split('_').first
  end

  def create_contact(contact)
    phone_number_from_jid = phone_number_from_jid(contact[:id])
    name = contact[:verifiedName].presence || contact[:name].presence || phone_number_from_jid
    ::ContactInboxWithContactBuilder.new(
      # FIXME: update the source_id to complete jid in future
      source_id: phone_number_from_jid,
      inbox: inbox,
      contact_attributes: { name: name, phone_number: "+#{phone_number_from_jid}" }
    ).perform
  end

  def handle_message(raw_message)
    jid = raw_message[:key][:remoteJid]
    return unless jid_user?(jid)

    id = raw_message[:key][:id]
    return if message_type(raw_message[:message]).in?(%w[protocol context unsupported])
    return if find_message_by_source_id(id) || message_under_process?(id)

    cache_message_source_id_in_redis(id)
    contact_inbox = find_contact_inbox(jid)

    unless contact_inbox.contact
      clear_message_source_id_from_redis(id)

      Rails.logger.warn "Contact not found for message: #{id}"
      return
    end

    create_message(raw_message, contact_inbox)
    clear_message_source_id_from_redis(id)
  end

  # TODO: Refactor this method in helpers to receive the raw message as an argument and remove it from here
  def message_type(message_content) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
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

  def find_message_by_source_id(source_id)
    return unless source_id

    Message.find_by(source_id: source_id).presence
  end

  def find_contact_inbox(jid)
    phone_number = phone_number_from_jid(jid)
    ::ContactInboxWithContactBuilder.new(
      # FIXME: update the source_id to complete jid in future
      source_id: phone_number
    ).perform
  end

  # TODO: Refactor this method in helpers to receive the source_id as an argument and remove it from here
  def message_under_process?(source_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: source_id)
    Redis::Alfred.get(key)
  end

  # TODO: Refactor this method in helpers to receive the source_id as an argument and remove it from here
  def cache_message_source_id_in_redis(source_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: source_id)
    ::Redis::Alfred.setex(key, true)
  end

  # TODO: Refactor this method in helpers to receive the source_id as an argument and remove it from here
  def clear_message_source_id_from_redis(source_id)
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: source_id)
    ::Redis::Alfred.delete(key)
  end

  def create_message(raw_message, contact_inbox) # rubocop:disable Metrics/AbcSize
    conversation = get_conversation(contact_inbox)
    inbox = contact_inbox.inbox
    message = conversation.messages.build(
      content: message_content(raw_message[:message]),
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: raw_message[:key][:id],
      sender: incoming?(raw_message) ? contact_inbox.contact : inbox.account.account_users.first.user,
      sender_type: incoming?(raw_message) ? 'Contact' : 'User',
      message_type: incoming?(raw_message) ? :incoming : :outgoing,
      content_attributes: message_content_attributes(raw_message),
      status: process_status(raw_message[:status]) || 'sent'
    )

    handle_attach_media(conversation, message, raw_message) if message_type(raw_message[:message]).in?(%w[image file video audio sticker])

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
  def incoming?(raw_message)
    !raw_message[:key][:fromMe]
  end

  # TODO: Refactor this method in helpers to receive the raw message as an argument and remove it from here
  def message_content(raw_message)
    raw_message.dig(:message, :conversation) ||
      raw_message.dig(:message, :extendedTextMessage, :text) ||
      raw_message.dig(:message, :imageMessage, :caption) ||
      raw_message.dig(:message, :videoMessage, :caption) ||
      raw_message.dig(:message, :documentMessage, :caption).presence ||
      raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :caption) ||
      raw_message.dig(:message, :reactionMessage, :text)
  end

  def message_content_attributes(raw_message)
    {
      external_created_at: baileys_extract_message_timestamp(raw_message[:messageTimestamp]),
      is_unsupported: message_type(raw_message[:message]) == 'unsupported' ? true : nil
    }.compact
  end

  def process_status(status)
    {
      'PENDING' => 'sent',
      'DELIVERY_ACK' => 'delivered',
      'READ' => 'read'
    }[status]
  end

  def handle_attach_media(message, conversation, raw_message)
    attachment_file = download_attachment_file(conversation, raw_message)
    message_type = message_type(raw_message[:message])
    file_type = file_content_type(message_type).to_s
    message_mimetype = message_mimetype(message_type, raw_message)
    attachment = message.attachments.build(
      account_id: message.account_id,
      file_type: file_type,
      file: { io: attachment_file, filename: filename(raw_message, message_mimetype, file_type), content_type: message_mimetype }
    )
    attachment.meta = { is_recorded_audio: true } if raw_message.dig(:message, :audioMessage, :ptt)
  rescue Down::Error => e
    message.update!(is_unsupported: true)

    Rails.logger.error "Failed to download attachment for message #{raw_message_id}: #{e.message}"
  end

  def download_attachment_file(conversation, raw_message)
    Down.download(conversation.inbox.channel.media_url(raw_message.dig(:key, :id)), headers: conversation.inbox.channel.api_headers)
  end

  def file_content_type(message_type)
    return :image if message_type.in?(%w[image sticker])
    return :video if message_type.in?(%w[video video_note])
    return :audio if message_type == 'audio'

    :file
  end

  def filename(raw_message, message_mimetype, file_content_type)
    filename = raw_message.dig[:message][:documentMessage][:fileName]
    return filename if filename.present?

    ext = ".#{message_mimetype.split(';').first.split('/').last}" if message_mimetype.present?
    "#{file_content_type}_#{raw_message[:key][:id]}_#{Time.current.strftime('%Y%m%d')}#{ext}"
  end

  def message_mimetype(message_type, raw_message)
    {
      'image' => raw_message.dig(:message, :imageMessage, :mimetype),
      'sticker' => raw_message.dig(:message, :stickerMessage, :mimetype),
      'video' => raw_message.dig(:message, :videoMessage, :mimetype),
      'audio' => raw_message.dig(:message, :audioMessage, :mimetype),
      'file' => raw_message.dig(:message, :documentMessage, :mimetype).presence ||
        raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :mimetype)
    }[message_type]
  end
end