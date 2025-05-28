module Whatsapp::BaileysHandlers::MessagesUpsert # rubocop:disable Metrics/ModuleLength
  include Whatsapp::IncomingMessageServiceHelpers
  include Whatsapp::BaileysHandlers::Helpers
  include BaileysHelper

  class AttachmentNotFoundError < StandardError; end

  private

  def process_messages_upsert
    messages = processed_params[:data][:messages]
    messages.each do |message|
      @message = nil
      @contact_inbox = nil
      @contact = nil
      @raw_message = message
      handle_message
    end
  end

  def handle_message
    return if jid_type != 'user'
    return if find_message_by_source_id(message_id) || message_under_process?
    return if message_type == 'protocol'

    cache_message_source_id_in_redis
    set_contact

    unless @contact
      clear_message_source_id_from_redis

      Rails.logger.warn "Contact not found for message: #{message_id}"
      return
    end

    set_conversation
    handle_create_message
    clear_message_source_id_from_redis
  end

  def set_contact
    push_name = contact_name
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      # FIXME: update the source_id to complete jid in future
      source_id: phone_number_from_jid,
      inbox: inbox,
      contact_attributes: { name: push_name, phone_number: "+#{phone_number_from_jid}" }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact

    @contact.update!(name: push_name) if @contact.name == phone_number_from_jid
  end

  def set_conversation
    # if lock to single conversation is disabled, we will create a new conversation if previous conversation is resolved
    @conversation = if @inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations
                                    .where.not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def handle_create_message
    return if message_type == 'protocol' ||
              (message_type == 'reaction' && message_content.blank?)

    create_message(attach_media: %w[image file video audio sticker].include?(message_type))
  end

  def create_message(attach_media: false)
    @message = @conversation.messages.build(
      content: message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      source_id: message_id,
      sender: incoming? ? @contact : @inbox.account.account_users.first.user,
      sender_type: incoming? ? 'Contact' : 'User',
      message_type: incoming? ? :incoming : :outgoing,
      content_attributes: message_content_attributes
    )

    handle_attach_media if attach_media

    @message.save!
  end

  def message_content_attributes
    content_attributes = { external_created_at: extract_baileys_message_timestamp(@raw_message[:messageTimestamp]) }
    if message_type == 'reaction'
      content_attributes[:in_reply_to_external_id] = @raw_message.dig(:message, :reactionMessage, :key, :id)
      content_attributes[:is_reaction] = true
    elsif message_type == 'unsupported'
      content_attributes[:is_unsupported] = true
    end

    content_attributes
  end

  def handle_attach_media
    begin
      attachment_file = download_attachment_file
    rescue Down::Error => e
      @message.update!(is_unsupported: true)

      Rails.logger.error "Failed to download attachment for message #{message_id}: #{e.message}"
      raise AttachmentNotFoundError
    end

    attachment = @message.attachments.build(
      account_id: @message.account_id,
      file_type: file_content_type.to_s,
      file: { io: attachment_file, filename: filename, content_type: message_mimetype }
    )
    attachment.meta = { is_recorded_audio: true } if @raw_message.dig(:message, :audioMessage, :ptt)
  end

  def download_attachment_file
    Down.download(@conversation.inbox.channel.media_url(@raw_message.dig(:key, :id)), headers: @conversation.inbox.channel.api_headers)
  end

  def filename
    filename = @raw_message.dig(:message, :documentMessage, :fileName)
    return filename if filename.present?

    ext = ".#{message_mimetype.split(';').first.split('/').last}" if message_mimetype.present?
    "#{file_content_type}_#{message_id}_#{Time.current.strftime('%Y%m%d')}#{ext}"
  end
end
