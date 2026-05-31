class Whatsapp::TemplateSubmitService
  TEMPLATE_NAME_REGEX = /\A[a-z0-9_]+\z/
  ALLOWED_CATEGORIES = %w[MARKETING UTILITY].freeze

  def initialize(whatsapp_channel:, template_payload:)
    @whatsapp_channel = whatsapp_channel
    @template_payload = template_payload.deep_stringify_keys
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def perform
    validate_payload!
    response = submit_to_meta
    process_response(response)
  end

  private

  def validate_payload!
    validate_name!
    validate_language!
    validate_category!
    validate_components!
  end

  def validate_name!
    name = @template_payload['name']
    raise invalid_template('Template name is required') if name.blank?
    raise invalid_template('Template name must be lowercase letters, numbers and underscores') unless name.match?(TEMPLATE_NAME_REGEX)
  end

  def validate_language!
    raise invalid_template('Template language is required') if @template_payload['language'].blank?
  end

  def validate_category!
    category = @template_payload['category']
    raise invalid_template('Template category is required') if category.blank?
    raise invalid_template("Template category must be one of: #{ALLOWED_CATEGORIES.join(', ')}") unless ALLOWED_CATEGORIES.include?(category)
  end

  def validate_components!
    components = @template_payload['components']
    raise invalid_template('Template components are required') if components.blank? || !components.is_a?(Array)

    has_body = components.any? { |component| component['type'].to_s.upcase == 'BODY' }
    raise invalid_template('Template must include a BODY component') unless has_body
  end

  def submit_to_meta
    HTTParty.post(
      "#{business_account_path}/message_templates",
      headers: api_headers,
      body: @template_payload.to_json,
      timeout: 15
    )
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, HTTParty::Error
    # Re-raise as an operator-safe submission error so the controller renders 422 instead of a raw 500.
    # The message is static: never interpolate the exception/response/headers, which carry the api_key.
    raise submission_error('Could not reach Meta, please retry')
  end

  def process_response(response)
    if response.success?
      { success: true, template_id: response['id'], status: response['status'] }
    else
      Rails.logger.error "WhatsApp template submission failed: #{response.code} - #{response.body}"
      raise submission_error(meta_error_message(response))
    end
  end

  def meta_error_message(response)
    parsed = JSON.parse(response.body)
    parsed.dig('error', 'error_user_msg') || parsed.dig('error', 'message') || 'Template submission failed'
  rescue JSON::ParserError
    'Template submission failed'
  end

  def invalid_template(message)
    CustomExceptions::Whatsapp::InvalidTemplate.new(message: message)
  end

  def submission_error(message)
    CustomExceptions::Whatsapp::TemplateSubmissionError.new(message: message)
  end

  def business_account_path
    "#{api_base_path}/#{@api_version}/#{@whatsapp_channel.provider_config['business_account_id']}"
  end

  def api_headers
    {
      'Authorization' => "Bearer #{@whatsapp_channel.provider_config['api_key']}",
      'Content-Type' => 'application/json'
    }
  end

  def api_base_path
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end
end
