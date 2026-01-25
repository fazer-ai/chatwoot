class Whatsapp::Providers::WhatsappBaileysService < Whatsapp::Providers::BaseService # rubocop:disable Metrics/ClassLength
  include BaileysHelper

  class MessageContentTypeNotSupported < StandardError; end
  class ProviderUnavailableError < StandardError; end

  DEFAULT_CLIENT_NAME = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME', nil)
  DEFAULT_URL = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_URL', nil)
  DEFAULT_API_KEY = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_API_KEY', nil)

  def self.status
    if DEFAULT_URL.blank? || DEFAULT_API_KEY.blank?
      raise ProviderUnavailableError, 'Missing BAILEYS_PROVIDER_DEFAULT_URL or BAILEYS_PROVIDER_DEFAULT_API_KEY setup'
    end

    response = HTTParty.get(
      "#{DEFAULT_URL}/status",
      headers: { 'x-api-key' => DEFAULT_API_KEY }
    )

    unless response.success?
      Rails.logger.error response.body
      raise ProviderUnavailableError, 'Baileys API is unavailable'
    end

    response.parsed_response.deep_symbolize_keys
  rescue ProviderUnavailableError
    raise
  rescue StandardError => e
    Rails.logger.error e.message
    raise ProviderUnavailableError, 'Baileys API is unavailable'
  end

  def setup_channel_provider
    response = HTTParty.post(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}",
      headers: api_headers,
      body: {
        clientName: DEFAULT_CLIENT_NAME,
        webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
        webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token'],
        # TODO: Remove on Baileys v2, default will be false
        includeMedia: false
      }.compact.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def disconnect_channel_provider
    response = HTTParty.delete(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}",
      headers: api_headers
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def send_message(recipient_id, message)
    @message = message
    @recipient_id = recipient_id

    if @message.content_attributes[:is_reaction]
      @message_content = reaction_message_content
    elsif @message.attachments.present?
      @message_content = attachment_message_content.merge(reply_context)
    elsif @message.outgoing_content.present?
      @message_content = { text: @message.outgoing_content }.merge(reply_context)
    else
      @message.update!(is_unsupported: true)
      return
    end

    send_message_request
  end

  def send_template(phone_number, template_info); end

  def sync_templates; end

  def media_url(media_id)
    "#{provider_url}/media/#{media_id}"
  end

  def api_headers
    { 'x-api-key' => api_key, 'Content-Type' => 'application/json' }
  end

  def validate_provider_config?
    response = HTTParty.get(
      "#{provider_url}/status/auth",
      headers: api_headers
    )

    process_response(response)
  end

  def toggle_typing_status(typing_status, recipient_id:, **)
    @recipient_id = recipient_id
    status_map = {
      Events::Types::CONVERSATION_TYPING_ON => 'composing',
      Events::Types::CONVERSATION_RECORDING => 'recording',
      Events::Types::CONVERSATION_TYPING_OFF => 'paused'
    }

    response = HTTParty.patch(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/presence",
      headers: api_headers,
      body: {
        toJid: remote_jid,
        type: status_map[typing_status]
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def update_presence(status)
    status_map = {
      'online' => 'available',
      'offline' => 'unavailable',
      'busy' => 'unavailable'
    }

    response = HTTParty.patch(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/presence",
      headers: api_headers,
      body: {
        type: status_map[status]
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def read_messages(messages, recipient_id:, **)
    @recipient_id = recipient_id

    response = HTTParty.post(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/read-messages",
      headers: api_headers,
      body: {
        keys: messages.map do |message|
          {
            id: message.source_id,
            remoteJid: remote_jid,
            fromMe: message.message_type == 'outgoing'
          }
        end
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def unread_message(recipient_id, message) # rubocop:disable Metrics/MethodLength
    @recipient_id = recipient_id

    response = HTTParty.post(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/chat-modify",
      headers: api_headers,
      body: {
        jid: remote_jid,
        mod: {
          markRead: false,
          lastMessages: [{
            key: {
              id: message.source_id,
              remoteJid: remote_jid,
              fromMe: message.message_type == 'outgoing'
            },
            messageTimestamp: message.content_attributes[:external_created_at]
          }]
        }
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def received_messages(recipient_id, messages)
    @recipient_id = recipient_id

    response = HTTParty.post(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/send-receipts",
      headers: api_headers,
      body: {
        keys: messages.map do |message|
          {
            id: message.source_id,
            remoteJid: remote_jid,
            fromMe: message.message_type == 'outgoing'
          }
        end
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def get_profile_pic(jid)
    response = HTTParty.get(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/profile-picture-url",
      headers: api_headers,
      query: { jid: jid },
      format: :json
    )

    return nil unless process_response(response)

    response.parsed_response
  end

  def on_whatsapp(recipient_id)
    @recipient_id = recipient_id

    response = HTTParty.post(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/on-whatsapp",
      headers: api_headers,
      body: {
        jids: [remote_jid]
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    response.parsed_response&.first || { 'jid' => remote_jid, 'exists' => false }
  end

  def delete_message(recipient_id, message)
    @recipient_id = recipient_id

    response = HTTParty.delete(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/messages",
      headers: api_headers,
      body: {
        jid: remote_jid,
        key: {
          id: message.source_id,
          remoteJid: remote_jid,
          fromMe: message.message_type == 'outgoing'
        }
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def edit_message(recipient_id, message, new_content)
    @recipient_id = recipient_id

    response = HTTParty.patch(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/messages",
      headers: api_headers,
      body: {
        jid: remote_jid,
        key: {
          id: message.source_id,
          remoteJid: remote_jid,
          fromMe: message.message_type == 'outgoing'
        },
        messageContent: { text: new_content }
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  private

  def provider_url
    whatsapp_channel.provider_config['provider_url'].presence || DEFAULT_URL
  end

  def api_key
    whatsapp_channel.provider_config['api_key'].presence || DEFAULT_API_KEY
  end

  def reaction_message_content
    reply_to = Message.find(@message.in_reply_to)
    {
      react: { key: { id: reply_to.source_id,
                      remoteJid: remote_jid,
                      fromMe: reply_to.message_type == 'outgoing' },
               text: @message.outgoing_content }
    }
  end

  def reply_context
    reply_to_external_id = @message.content_attributes[:in_reply_to_external_id]
    return {} if reply_to_external_id.blank?

    reply_to_message = @message.conversation.messages.find_by(source_id: reply_to_external_id)
    return {} unless reply_to_message

    {
      quotedMessage: {
        key: {
          id: reply_to_external_id,
          remoteJid: remote_jid,
          fromMe: reply_to_message.message_type == 'outgoing'
        },
        message: quoted_message_content(reply_to_message)
      }
    }
  end

  def quoted_message_content(message)
    if message.attachments.present?
      attachment = message.attachments.first
      case attachment.file_type
      when 'image'
        { imageMessage: { caption: message.content } }
      when 'video'
        { videoMessage: { caption: message.content } }
      when 'audio'
        { audioMessage: {} }
      when 'file'
        { documentMessage: { caption: message.content, fileName: attachment.file.filename.to_s } }
      else
        { conversation: message.content.to_s }
      end
    else
      { conversation: message.content.to_s }
    end
  end

  def attachment_message_content # rubocop:disable Metrics/MethodLength
    attachment = @message.attachments.first
    buffer = attachment_to_base64(attachment)

    content = {
      fileName: attachment.file.filename,
      caption: @message.outgoing_content
    }
    case attachment.file_type
    when 'image'
      content[:image] = buffer
    when 'audio'
      content[:audio] = buffer
      content[:ptt] = attachment.meta&.dig('is_recorded_audio')
    when 'file'
      content[:document] = buffer
      content[:mimetype] = attachment.file.content_type
    when 'sticker'
      content[:sticker] = buffer
    when 'video'
      content[:video] = buffer
    end

    content.compact
  end

  def send_message_request
    response = HTTParty.post(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/send-message",
      headers: api_headers,
      body: {
        jid: remote_jid,
        messageContent: @message_content
      }.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    update_external_created_at(response)
    response.parsed_response.dig('data', 'key', 'id')
  end

  def process_response(response)
    Rails.logger.error response.body unless response.success?
    response.success?
  end

  def remote_jid
    return @recipient_id if @recipient_id.ends_with?('@lid')

    "#{@recipient_id.delete('+')}@s.whatsapp.net"
  end

  def update_external_created_at(response)
    timestamp = response.parsed_response.dig('data', 'messageTimestamp')
    return unless timestamp

    external_created_at = baileys_extract_message_timestamp(timestamp)
    @message.update!(external_created_at: external_created_at)
  end

  private_class_method def self.with_error_handling(*method_names)
    method_names.each do |method_name|
      original_method = instance_method(method_name)

      define_method("#{method_name}_without_error_handling") do |*args, **kwargs, &block|
        original_method.bind_call(self, *args, **kwargs, &block)
      end

      define_method(method_name) do |*args, **kwargs, &block|
        original_method.bind_call(self, *args, **kwargs, &block)
      rescue StandardError => e
        handle_channel_error
        raise e
      end
    end
  end

  def handle_channel_error
    whatsapp_channel.update_provider_connection!(connection: 'close')

    return if @handling_error

    @handling_error = true
    begin
      setup_channel_provider_without_error_handling
    rescue StandardError => e
      Rails.logger.error "Failed to reconnect channel after error: #{e.message}"
    ensure
      @handling_error = false
    end
  end

  with_error_handling :setup_channel_provider,
                      :disconnect_channel_provider,
                      :send_message,
                      :toggle_typing_status,
                      :update_presence,
                      :read_messages,
                      :unread_message,
                      :received_messages,
                      :on_whatsapp,
                      :delete_message,
                      :edit_message
end
