class Whatsapp::Providers::WhatsappZapiService < Whatsapp::Providers::BaseService # rubocop:disable Metrics/ClassLength
  include Whatsapp::TransportFailure
  include Whatsapp::CredentialCheck
  include Whatsapp::ZapiRequestOptions

  # See the note in WhatsappBaileysService: legacy errors share the session hierarchy.
  class ProviderUnavailableError < Whatsapp::Session::Errors::ProviderUnavailable; end

  API_BASE_PATH = 'https://api.z-api.io'.freeze

  def send_template(phone_number, template_info); end

  def sync_templates; end

  def send_message(phone, message)
    phone = phone.delete('+')
    params = message.content_attributes[:zapi_args].presence || {}

    params[:messageId] = message.in_reply_to_external_id if message.in_reply_to_external_id.present?

    if message.content_attributes[:is_reaction]
      send_reaction_message(phone, message, **params)
    elsif message.attachments.present?
      handle_message_with_attachment(message, phone, **params)
    elsif message.outgoing_content.present?
      send_text_message(phone, message, **params)
    else
      message.update!(is_unsupported: true)
      nil
    end
  end

  def validate_provider_config?
    url = "#{api_instance_path_with_token}/status"
    headers = api_headers
    response = credential_check_request { HTTParty.get(url, headers: headers, **ZAPI_REQUEST_OPTIONS) }
    ensure_credential_verdict!(response)

    process_response(response)
  end

  def setup_channel_provider
    register_webhooks

    if whatsapp_channel.provider_connection.blank? || whatsapp_channel.provider_connection['connection'] == 'close'
      Channels::Whatsapp::ZapiQrCodeJob.perform_later(whatsapp_channel)
    end

    true
  end

  # Z-API signs nothing and echoes no secret back, so the URL it posts to is the credential.
  # The token is stored before Z-API hears of it, because a registration Z-API applied but
  # whose answer never arrived would otherwise leave Z-API posting a token this app does not
  # know. The old URL stays open for the inbox until the new one is confirmed, by Z-API
  # accepting it here or by its first delivery (Webhooks::Whatsapp::ZapiController), so a
  # failed registration costs nothing. An inbox from before this URL existed gets its token
  # here too, which is how Migration::ZapiWebhookUrlJob moves it.
  def register_webhooks
    token = reserve_webhook_verify_token

    response = HTTParty.put(
      "#{api_instance_path_with_token}/update-every-webhooks",
      headers: api_headers,
      body: {
        value: webhook_url(token),
        notifySentByMe: true
      }.to_json,
      **ZAPI_REQUEST_OPTIONS
    )

    raise ProviderUnavailableError unless process_response(response)

    confirm_webhook_url
  end

  def confirm_webhook_url
    return if whatsapp_channel.provider_config['webhook_url_confirmed']

    update_provider_config { |config| config.merge('webhook_url_confirmed' => true) }
  end

  def disconnect_channel_provider
    response = HTTParty.get(
      "#{api_instance_path_with_token}/disconnect",
      headers: api_headers,
      **ZAPI_REQUEST_OPTIONS
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  def qr_code_image
    response = HTTParty.get(
      "#{api_instance_path_with_token}/qr-code/image",
      headers: api_headers,
      **ZAPI_REQUEST_OPTIONS
    )

    if response.parsed_response['connected']
      whatsapp_channel.update_provider_connection!(connection: 'open')
      return
    end

    return unless process_response(response)

    response.parsed_response['value']
  end

  def read_messages(messages, recipient_id:, **)
    phone = recipient_id.delete('+')

    messages.each do |message|
      next if message.source_id.blank?

      Channels::Whatsapp::ZapiReadMessageJob.perform_later(whatsapp_channel, phone, message.source_id)
    end

    true
  end

  def send_read_message(phone, message_source_id)
    response = HTTParty.post(
      "#{api_instance_path_with_token}/read-message",
      headers: api_headers,
      body: {
        phone: phone,
        messageId: message_source_id
      }.to_json,
      **ZAPI_REQUEST_OPTIONS
    )

    process_response(response)
  end

  def on_whatsapp(phone_number)
    response = HTTParty.get(
      "#{api_instance_path_with_token}/phone-exists/#{phone_number.delete('+')}",
      headers: api_headers,
      **ZAPI_REQUEST_OPTIONS
    )

    raise ProviderUnavailableError unless process_response(response)

    response.parsed_response || { 'exists' => false, 'phone' => nil, 'lid' => nil }
  end

  def delete_message(recipient_id, message)
    return false if recipient_id.blank?

    phone = recipient_id.delete('+')

    response = HTTParty.delete(
      "#{api_instance_path_with_token}/messages",
      headers: api_headers,
      query: {
        messageId: message.source_id,
        phone: phone,
        owner: message.message_type == 'outgoing'
      },
      **ZAPI_REQUEST_OPTIONS
    )

    raise ProviderUnavailableError unless process_response(response)

    true
  end

  private

  def webhook_url(token)
    "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/whatsapp/zapi/#{whatsapp_channel.id}/#{token}"
  end

  # Under the row lock, so a migration and a setup racing on the same inbox settle on one token.
  def reserve_webhook_verify_token
    update_provider_config do |config|
      config['webhook_verify_token'].present? ? config : config.merge('webhook_verify_token' => SecureRandom.hex(16))
    end
    whatsapp_channel.provider_config['webhook_verify_token']
  end

  # Merged into the row as it is under the lock, not into the copy this service was handed,
  # so a credential edit saved in between is not written over.
  def update_provider_config
    whatsapp_channel.with_lock do
      updated = yield whatsapp_channel.provider_config
      next if updated == whatsapp_channel.provider_config

      whatsapp_channel.provider_config = updated
      whatsapp_channel.save!(validate: false)
    end
  end

  def api_instance_path
    "#{API_BASE_PATH}/instances/#{whatsapp_channel.provider_config['instance_id']}"
  end

  def api_instance_path_with_token
    "#{api_instance_path}/token/#{whatsapp_channel.provider_config['token']}"
  end

  def api_headers
    { 'Content-Type' => 'application/json', 'Client-Token' => whatsapp_channel.provider_config['client_token'] }
  end

  def process_response(response)
    Rails.logger.error response.body unless response.success?
    response.success?
  end

  def send_text_message(phone, message, **params)
    response = post_outgoing(
      "#{api_instance_path_with_token}/send-text",
      headers: api_headers,
      body: {
        phone: phone,
        message: message.outgoing_content,
        **params
      }.compact.to_json
    )

    unless process_response(response)
      message.update!(status: :failed, external_error: response.parsed_response&.dig('error'))
      raise ProviderUnavailableError
    end

    response.parsed_response&.dig('messageId')
  end

  def handle_message_with_attachment(message, phone, **params)
    attachment = message.attachments.first

    if attachment.file.byte_size > max_size(attachment)
      message.update!(status: :failed, external_error: 'File too large')
      return
    end

    base64_data = attachment_to_base64(attachment)
    buffer = "data:#{attachment.file.content_type};base64,#{base64_data}"

    case attachment.file_type
    when 'image'
      send_image_message(phone, message, buffer, **params)
    when 'audio'
      send_audio_message(phone, message, buffer, **params)
    when 'file'
      send_document_message(phone, message, attachment, buffer, **params)
    when 'video'
      send_video_message(phone, message, buffer, **params)
    end
  end

  def max_size(attachment)
    case attachment.file_type
    when 'image'
      5.megabytes
    when 'audio', 'video'
      16.megabytes
    else
      100.megabytes
    end
  end

  def send_image_message(phone, message, buffer, **params)
    response = post_outgoing(
      "#{api_instance_path_with_token}/send-image",
      headers: api_headers,
      body: {
        phone: phone,
        image: buffer,
        caption: message.outgoing_content,
        **params
      }.compact.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    response.parsed_response&.dig('messageId')
  end

  def send_audio_message(phone, _message, buffer, **params)
    response = post_outgoing(
      "#{api_instance_path_with_token}/send-audio",
      headers: api_headers,
      body: {
        phone: phone,
        audio: buffer,
        waveform: true,
        **params
      }.compact.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    response.parsed_response&.dig('messageId')
  end

  def send_document_message(phone, message, attachment, buffer, **params)
    file_extension = File.extname(attachment.file.filename.to_s).delete('.')
    if file_extension.blank?
      Rails.logger.warn "Missing file extension for attachment: #{attachment.id}"
      file_extension = 'bin'
    end

    response = post_outgoing(
      "#{api_instance_path_with_token}/send-document/#{file_extension}",
      headers: api_headers,
      body: {
        phone: phone,
        document: buffer,
        fileName: attachment.file.filename.to_s,
        caption: message.outgoing_content,
        **params
      }.compact.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    response.parsed_response&.dig('messageId')
  end

  def send_video_message(phone, message, buffer, **params)
    response = post_outgoing(
      "#{api_instance_path_with_token}/send-video",
      headers: api_headers,
      body: {
        phone: phone,
        video: buffer,
        caption: message.outgoing_content,
        **params
      }.compact.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    response.parsed_response&.dig('messageId')
  end

  def send_reaction_message(phone, message, **params)
    response = post_outgoing(
      "#{api_instance_path_with_token}/send-reaction",
      headers: api_headers,
      body: {
        phone: phone,
        reaction: message.outgoing_content,
        messageId: message.in_reply_to_external_id,
        **params
      }.compact.to_json
    )

    raise ProviderUnavailableError unless process_response(response)

    response.parsed_response&.dig('messageId')
  end

  # Every HTTP call that puts a message on its way out goes through here, and nothing else does.
  # One line inside the `rescue`, on purpose: see Whatsapp::TransportFailure.
  def post_outgoing(url, **)
    HTTParty.post(url, **, **ZAPI_SEND_OPTIONS)
  rescue StandardError => e
    raise_transport_failure(e)
  end
end
