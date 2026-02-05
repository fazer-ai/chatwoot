module Whatsapp::BaileysHandlers::MessagesUpsert # rubocop:disable Metrics/ModuleLength
  include Whatsapp::BaileysHandlers::Helpers
  include BaileysHelper

  private

  def process_messages_upsert
    messages = processed_params[:data][:messages]
    messages.each do |message|
      @message = nil
      @contact_inbox = nil
      @contact = nil
      @raw_message = message

      next handle_message if incoming?

      # NOTE: Shared lock with Whatsapp::SendOnWhatsappService
      # Avoids race conditions when sending messages.
      with_baileys_channel_lock_on_outgoing_message(inbox.channel.id) { handle_message }
    end
  end

  def handle_message # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
    @lock_acquired = false

    return unless %w[lid user].include?(jid_type)
    return unless extract_from_jid(type: 'lid')
    return if ignore_message?
    return if find_message_by_source_id(raw_message_id)

    @lock_acquired = acquire_message_processing_lock
    return unless @lock_acquired

    # Lock by contact phone to prevent race conditions when multiple messages
    # from the same contact arrive simultaneously (e.g., WhatsApp albums).
    contact_phone = extract_from_jid(type: 'pn') || extract_from_jid(type: 'lid')
    with_contact_lock(contact_phone) do
      # Re-check after acquiring lock to handle race conditions where:
      # 1. An agent sends a message from Chatwoot (slow API call)
      # 2. WhatsApp sends webhook before source_id is saved
      # 3. Webhook handler times out waiting for channel lock and proceeds
      # 4. By now, source_id should be set, so we can find the message
      return if find_message_by_source_id(raw_message_id)

      set_contact

      unless @contact
        Rails.logger.warn "Contact not found for message: #{raw_message_id}"
        return
      end

      set_conversation
      handle_create_message
    end
  ensure
    clear_message_source_id_from_redis if @lock_acquired
  end

  def set_contact
    phone = extract_from_jid(type: 'pn')
    source_id = extract_from_jid(type: 'lid')
    identifier = "#{source_id}@lid"

    Whatsapp::ContactInboxConsolidationService.new(
      inbox: inbox,
      phone: phone,
      lid: source_id,
      identifier: identifier
    ).perform

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: source_id,
      inbox: inbox,
      contact_attributes: { name: contact_name, phone_number: ("+#{phone}" if phone), identifier: identifier }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact

    update_contact_info(phone, source_id, identifier)
  end

  def update_contact_info(phone, source_id, identifier)
    update_params = {}
    update_params[:phone_number] = "+#{phone}" if phone
    update_params[:identifier] = identifier
    update_params[:name] = contact_name if @contact.name.in?([phone, source_id, identifier])

    @contact.update!(update_params) if update_params.present?
    try_update_contact_avatar
  end

  def handle_create_message
    create_message(attach_media: %w[image file video audio sticker].include?(message_type))
  end

  def create_message(attach_media: false)
    @message = @conversation.messages.build(
      content: message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      source_id: raw_message_id,
      sender: incoming? ? @contact : nil,
      message_type: incoming? ? :incoming : :outgoing,
      content_attributes: message_content_attributes
    )

    handle_attach_media if attach_media

    @message.save!

    inbox.channel.received_messages([@message], @conversation) if incoming?
  end

  def message_content_attributes
    type = message_type
    msg = unwrap_ephemeral_message(@raw_message[:message])
    content_attributes = { external_created_at: baileys_extract_message_timestamp(@raw_message[:messageTimestamp]) }
    content_attributes[:external_sender_name] = 'WhatsApp' unless incoming?
    if type == 'reaction'
      content_attributes[:in_reply_to_external_id] = msg.dig(:reactionMessage, :key, :id)
      content_attributes[:is_reaction] = true
    elsif reply_to_message_id
      content_attributes[:in_reply_to_external_id] = reply_to_message_id
    elsif type == 'unsupported'
      content_attributes[:is_unsupported] = true
    end

    content_attributes
  end

  def handle_attach_media
    attachment_file = download_attachment_file
    msg = unwrap_ephemeral_message(@raw_message[:message])

    attachment = @message.attachments.build(
      account_id: @message.account_id,
      file_type: file_content_type.to_s,
      file: { io: attachment_file, filename: filename, content_type: message_mimetype }
    )
    attachment.meta = { is_recorded_audio: true } if msg.dig(:audioMessage, :ptt)
  rescue Down::Error => e
    @message.update!(is_unsupported: true)

    Rails.logger.error "Failed to download attachment for message #{raw_message_id}: #{e.message}"
  end

  def download_attachment_file
    Down.download(@conversation.inbox.channel.media_url(@raw_message.dig(:key, :id)), headers: @conversation.inbox.channel.api_headers)
  end

  def filename
    msg = unwrap_ephemeral_message(@raw_message[:message])
    filename = msg.dig(:documentMessage, :fileName) || msg.dig(:documentWithCaptionMessage, :message, :documentMessage, :fileName)
    return filename if filename.present?

    ext = ".#{message_mimetype.split(';').first.split('/').last}" if message_mimetype.present?
    "#{file_content_type}_#{raw_message_id}_#{Time.current.strftime('%Y%m%d')}#{ext}"
  end
end
