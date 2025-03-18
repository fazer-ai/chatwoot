class Whatsapp::Providers::WhatsappBaileysService < Whatsapp::Providers::BaseService
  def disconnect_channel_provider
    response = HTTParty.delete(
      "#{api_connection_path}/#{phone_number}",
      headers: api_headers
    )

    Rails.logger.error response.body unless response.success?
    response
  end

  def send_message(phone_number, message)
    response = HTTParty.post(
      "#{api_send_path}/#{phone_number}",
      headers: api_headers,
      body: {
        type: 'text',
        text: { body: message.content }
      }.to_json
    )

    if response.success?
      response['messages'].first['id']
    else
      Rails.logger.error response.body
      nil
    end
  end

  def send_template(phone_number, template_info); end

  def sync_templates; end

  def media_url(media_id); end

  def api_headers
    { 'x-api-key' => whatsapp_channel.provider_config['api_key'], 'Content-Type' => 'application/json' }
  end

  def validate_provider_config?
    response = HTTParty.post(
      "#{api_connection_path}/#{phone_number}",
      headers: api_headers,
      body: {
        clientName: 'CHATWOOT',
        webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
        webhookVerifyToken: whatsapp_channel.ensure_webhook_verify_token
      }.to_json
    )

    Rails.logger.error response.body unless response.success?
    response.success?
  end

  private

  def api_base_path
    ENV.fetch('BAILEYS_BASE_URL', 'http://localhost:3025')
  end

  def api_connection_path
    "#{api_base_path}/connections"
  end

  def api_send_path
    "#{api_base_path}/send"
  end

  def process_response(response)
    if response.success?
      response['messages'].first['id']
    else
      Rails.logger.error response.body
      nil
    end
  end
end
