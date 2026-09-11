class Whatsapp::WebhookSetupService
  def initialize(channel, waba_id = nil, access_token = nil)
    @channel = channel
    @waba_id = waba_id || channel.provider_config['business_account_id']
    @access_token = access_token || channel.provider_config['api_key']
    @api_client = Whatsapp::FacebookApiClient.new(@access_token)
  end

  def perform
    validate_parameters!

    register_phone_number if registration_needed?

    setup_webhook
  end

  def register_callback
    validate_parameters!
    setup_webhook
  end

  private

  def validate_parameters!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'WABA ID is required' if @waba_id.blank?
    raise ArgumentError, 'Access token is required' if @access_token.blank?
    raise ArgumentError, 'Phone number ID is required' if @channel.provider_config['phone_number_id'].blank?
  end

  def register_phone_number
    phone_number_id = @channel.provider_config['phone_number_id']
    pin = fetch_or_create_pin
    # Stored before the call, not after. The write can time out after Meta already received it, and
    # then the PIN Meta may be holding is the one this attempt drew. Storing it afterwards meant an
    # attempt whose outcome nobody saw left nothing behind, and the next one drew a different PIN,
    # so the app could not name what might already be valid on Meta's side (#590).
    store_pin(pin)

    @api_client.register_phone_number(phone_number_id, pin)
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP] Phone registration #{registration_outcome(e)} but continuing " \
                      "(phone_number_id #{phone_number_id}, pin #{pin}): #{e.message}")
  end

  # A refusal and a silence are different facts and used to share one sentence. Meta answering "no"
  # is something the app knows; a read that never came back is something it does not, and the number
  # may well be registered on Meta's side with the PIN this attempt stored.
  def registration_outcome(error)
    error.is_a?(Timeout::Error) || error.is_a?(IOError) || error.is_a?(SystemCallError) ? 'outcome unknown' : 'refused'
  end

  def fetch_or_create_pin
    # Check if we have a stored PIN for this phone number
    existing_pin = @channel.provider_config['verification_pin']
    return existing_pin.to_i if existing_pin.present?

    # Generate a new 6-digit PIN if none exists
    SecureRandom.random_number(900_000) + 100_000
  end

  # `save!(validate: false)`, the way every other write to provider_config in this area does it
  # (Channel::Whatsapp#enable_voice_calling! and friends). A plain `save!` runs
  # `validate_provider_config`, which is itself a Graph call, and this one runs on the path where
  # Meta is already misbehaving: a failed re-check would raise, the rescue above would swallow it,
  # and the registration write would never leave. Writing down the PIN we are about to send must
  # not depend on Meta answering a different question first.
  def store_pin(pin)
    @channel.provider_config['verification_pin'] = pin
    @channel.save!(validate: false)
  end

  def setup_webhook
    callback_url = build_callback_url
    verify_token = @channel.provider_config['webhook_verify_token']
    phone_number_id = @channel.provider_config['phone_number_id']

    @api_client.subscribe_phone_number_webhook(@waba_id, phone_number_id, callback_url, verify_token, subscribed_fields: subscribed_fields)
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Webhook setup failed: #{e.message}")
    raise "Webhook setup failed: #{e.message}"
  end

  # Subscribe to `calls` only when voice calling is enabled on the inbox
  def subscribed_fields
    fields = %w[messages smb_message_echoes]
    fields << 'calls' if calls_enabled_on_waba?
    fields
  end

  # `subscribed_fields` is a WABA-wide app subscription, so keep `calls` whenever this inbox or
  # any sibling on the same WABA has voice on — otherwise a non-calling sibling's setup would
  # rewrite the shared subscription and drop calls for a calling-enabled sibling.
  def calls_enabled_on_waba?
    return true if @channel.provider_config['calling_enabled']

    Channel::Whatsapp
      .where(provider: 'whatsapp_cloud')
      .where.not(id: @channel.id)
      .where("provider_config->>'business_account_id' = ?", @waba_id)
      .where("provider_config->>'calling_enabled' = 'true'")
      .exists?
  end

  def build_callback_url
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    phone_number = @channel.phone_number

    "#{frontend_url}/webhooks/whatsapp/#{phone_number}"
  end

  # Registering is a write to Meta plus a PIN on the channel, so it happens on a definite "no" and
  # never on a silence. Both reads below answer three things, not two, and the third one used to be
  # spelled with the same word as "no" (#590).
  #
  # The order is load-bearing and is the one the old `||` produced, so the calls stay where they
  # were: a definite "not verified" registers without asking health at all, and anything else asks,
  # because health names the pending state on its own. What is new is only that "could not tell"
  # takes the second branch instead of the first.
  def registration_needed?
    return true if verification_state == :not_verified

    pending_state == :pending
  end

  # `:verified`, `:not_verified`, `:unknown`. `:unknown` covers the read that never came back AND
  # the 200 that came back without the field, which never reached a rescue at all: it used to turn
  # into `false` inside the client, one layer further down than anyone was looking.
  def verification_state
    phone_number_id = @channel.provider_config['phone_number_id']
    status = @api_client.phone_number_code_verification_status(phone_number_id)

    if status.blank?
      Rails.logger.error("[WHATSAPP] Phone number #{phone_number_id} answered no code verification status; " \
                         'not deciding registration from it')
      return :unknown
    end

    Rails.logger.info("[WHATSAPP] Phone number #{phone_number_id} code verification status: #{status}")
    status == 'VERIFIED' ? :verified : :not_verified
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Could not read the code verification status for #{phone_number_id}; " \
                       "not deciding registration from it: #{e.message}")
    :unknown
  end

  # `:pending`, `:not_pending`, `:unknown`. Same vocabulary on purpose: this axis already defaulted
  # the harmless way when it could not tell, and saying so out loud is what keeps the next reader
  # from restoring the other one.
  #
  # `platform_type: NOT_APPLICABLE` means not fully set up, and `throughput.level: NOT_APPLICABLE`
  # means no messaging capacity assigned. Either one is the pending provisioning state.
  def pending_state
    health_data = Whatsapp::HealthService.new(@channel).fetch_health_status

    pending = health_data[:platform_type] == 'NOT_APPLICABLE' ||
              health_data.dig(:throughput, :level) == 'NOT_APPLICABLE'
    pending ? :pending : :not_pending
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Could not read the health status; not deciding registration from it: #{e.message}")
    :unknown
  end
end
