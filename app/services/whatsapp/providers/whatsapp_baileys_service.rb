class Whatsapp::Providers::WhatsappBaileysService < Whatsapp::Providers::BaseService
  class MessageContentTypeNotSupported < StandardError; end
  class MessageSendFailed < StandardError; end

  DEFAULT_CLIENT_NAME = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME', nil)
  DEFAULT_URL = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_URL', nil)
  DEFAULT_API_KEY = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_API_KEY', nil)

  def setup_channel_provider
    response = HTTParty.post(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}",
      headers: api_headers,
      body: {
        clientName: DEFAULT_CLIENT_NAME,
        webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
        webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token']
      }.to_json
    )

    process_response(response)
  end

  def disconnect_channel_provider
    response = HTTParty.delete(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}",
      headers: api_headers
    )

    process_response(response)
  end

  def send_message(phone_number, message)
    if message.content_type != 'text' || message.content.blank?
      message.update!(content: I18n.t('errors.messages.send.unsupported'), status: 'failed')
      raise MessageContentTypeNotSupported
    end

    return unless message.status == 'sent'

    @message = message
    @phone_number = phone_number
    if message.attachments.present?
      send_attachment_message
    elsif message.content_type == 'input_select'
      send_interactive_text_message
    else
      send_text_message
    end
  end

  def send_template(phone_number, template_info); end

  def sync_templates; end

  def media_url(media_id); end

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

  private

  def provider_url
    whatsapp_channel.provider_config['provider_url'].presence || DEFAULT_URL
  end

  def api_key
    whatsapp_channel.provider_config['api_key'].presence || DEFAULT_API_KEY
  end

  def send_attachment_message
    raise NotImplementedError, 'Attachment message sending is not implemented for Baileys provider'
  end

  def send_interactive_text_message
    raise NotImplementedError, 'Interactive text message sending is not implemented for Baileys provider'
  end

  def send_text_message
    response = HTTParty.post(
      "#{provider_url}/connections/#{whatsapp_channel.phone_number}/send-message",
      headers: api_headers,
      body: {
        type: 'text',
        recipient: @phone_number,
        message: @message.content
      }.to_json
    )

    return response.parsed_response.dig('data', 'key', 'id') if process_response(response)

    @message.update!(status: 'failed')
    raise MessageSendFailed
  end

  def process_response(response)
    Rails.logger.error response.body unless response.success?
    response.success?
  end

  private_class_method def self.with_error_handling(*method_names)
    method_names.each do |method_name|
      original_method = instance_method(method_name)

      define_method(method_name) do |*args, &block|
        original_method.bind_call(self, *args, &block)
      rescue StandardError => e
        handle_channel_error
        raise e
      end
    end
  end

  def handle_channel_error
    whatsapp_channel.update_provider_connection!(connection: 'close')
  end

  with_error_handling :setup_channel_provider, :disconnect_channel_provider, :send_message
end
