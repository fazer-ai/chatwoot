class Whatsapp::Providers::WhatsappBaileysService < Whatsapp::Providers::BaseService
  def setup_channel_provider
    response = HTTParty.post(
      "#{api_base_path}/connections/#{phone_number}",
      headers: api_headers,
      body: {
        clientName: client_name,
        webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
        webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token']
      }.to_json
    )

    process_response(response)
  end

  def disconnect_channel_provider
    response = HTTParty.delete(
      "#{api_base_path}/connections/#{phone_number}",
      headers: api_headers
    )

    process_response(response)
  end

  def send_message(to_phone_number, message)
    response = HTTParty.post(
      "#{api_base_path}/connections/#{phone_number}/send-message",
      headers: api_headers,
      body: {
        type: 'text',
        to: to_phone_number,
        text: { body: message.content }
      }.to_json
    )

    process_response(response)
  end

  def send_template(phone_number, template_info); end

  def sync_templates; end

  def media_url(media_id); end

  def api_headers
    { 'x-api-key' => api_key, 'Content-Type' => 'application/json' }
  end

  # FIXME: This method should implement specs
  def validate_provider_config?
    return true if Rails.env.test?

    response = HTTParty.get(
      "#{api_base_path}/status",
      headers: api_headers
    )

    process_response(response)
  end

  private_class_method def self.with_error_handling(*method_names)
    method_names.each do |method_name|
      original_method = instance_method(method_name)

      define_method(method_name) do |*args, &block|
        original_method.bind_call(self, *args, &block)
      rescue StandardError => e
        whatsapp_channel.update!(provider_connection: { connection: 'close' })
        raise e
      end
    end
  end

  with_error_handling :setup_channel_provider, :disconnect_channel_provider, :send_message

  private

  def phone_number
    whatsapp_channel.phone_number
  end

  def client_namea
    ENV.fetch('BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME', nil)
  end

  def api_base_path
    whatsapp_channel.provider_config['provider_url'].presence || ENV.fetch('BAILEYS_PROVIDER_DEFAULT_URL')
  end

  def api_key
    whatsapp_channel.provider_config['api_key'].presence || ENV.fetch('BAILEYS_PROVIDER_DEFAULT_API_KEY')
  end

  def process_response(response)
    Rails.logger.error response.body unless response.success?
    response.success?
  end
end
