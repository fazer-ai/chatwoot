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

    Rails.logger.error response.body unless response.success?
    response.success?
  end

  def send_template(phone_number, template_info); end

  def sync_templates; end

  def media_url(media_id); end

  def api_headers
    { 'x-api-key' => whatsapp_channel.provider_config['api_key'], 'Content-Type' => 'application/json' }
  end

  def validate_provider_config?
    true
  end

  private

  def phone_number
    whatsapp_channel.phone_number
  end

  def client_name
    ENV.fetch('DEFAULT_BAILEYS_CLIENT_NAME', 'Chatwoot')
  end

  def api_base_path
    # TODO: Remove default and raise error if not set
    ENV.fetch('DEFAULT_BAILEYS_BASE_URL', 'http://localhost:3025')
  end

  def process_response(response)
    Rails.logger.error response.body unless response.success?
    response.success?
  end
end
