class Whatsapp::FacebookApiClient
  include Whatsapp::GraphRequestOptions

  BASE_URI = 'https://graph.facebook.com'.freeze
  # Base webhook fields resent on every subscribe so Meta won't reset to defaults. `calls` is added by callers only when voice is enabled.
  WEBHOOK_DEFAULT_FIELDS = %w[messages smb_message_echoes].freeze

  def initialize(access_token = nil)
    @access_token = access_token
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def exchange_code_for_token(code)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/oauth/access_token",
      **GRAPH_REQUEST_OPTIONS,
      query: {
        client_id: GlobalConfigService.load('WHATSAPP_APP_ID', ''),
        client_secret: GlobalConfigService.load('WHATSAPP_APP_SECRET', ''),
        code: code
      }
    )

    handle_response(response, 'Token exchange failed')
  end

  def fetch_phone_numbers(waba_id)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/phone_numbers",
      **GRAPH_REQUEST_OPTIONS,
      query: { access_token: @access_token }
    )

    handle_response(response, 'WABA phone numbers fetch failed')
  end

  def debug_token(input_token)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/debug_token",
      **GRAPH_REQUEST_OPTIONS,
      query: {
        input_token: input_token,
        access_token: build_app_access_token
      }
    )

    handle_response(response, 'Token validation failed')
  end

  def register_phone_number(phone_number_id, pin)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}/register",
      **GRAPH_REQUEST_OPTIONS,
      headers: request_headers,
      body: { messaging_product: 'whatsapp', pin: pin.to_s }.to_json
    )

    handle_response(response, 'Phone registration failed')
  end

  # Releases the number from this app so it can be re-added under another app/BSP. Without this,
  # after an inbox is deleted the number stays registered and Meta reports "already in a partner app".
  def deregister_phone_number(phone_number_id)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}/deregister",
      **GRAPH_REQUEST_OPTIONS,
      headers: request_headers
    )

    handle_response(response, 'Phone deregistration failed')
  end

  # Answers Meta's status, not a verdict on it, and `nil` when the answer did not carry one.
  # `code_verification_status` can be absent from a perfectly good 200, and a missing field is not
  # the same fact as `NOT_VERIFIED`. Collapsing both into `false` here is what let a read that
  # answered nothing reach the caller looking like a read that said no (#590), and the caller
  # writes to Meta on that.
  def phone_number_code_verification_status(phone_number_id)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      **GRAPH_REQUEST_OPTIONS,
      headers: request_headers
    )

    handle_response(response, 'Phone status check failed')['code_verification_status']
  end

  # Two calls, and only the first decides whether anything arrives at all.
  #
  # Subscribe app to WABA first — Meta requires it before any callback override (issue #13097).
  # subscribed_fields (incl. `calls` when voice is enabled) is declared here; the phone-level POST has no such field.
  #
  # The phone-level override takes precedence over WABA-level, so numbers on one WABA can route to different URLs.
  # It is also the half Meta refuses for a whole class of accounts that receive perfectly well without it: a
  # coexistence number whose WABA sits in the customer's own Business Manager answers `(#200) Permissions error`,
  # because the integrator's system user cannot manage a WABA in another portfolio. Under one rescue that refusal
  # reached `Channel::Whatsapp#setup_webhooks` as a setup failure, marked the channel for reauthorization, and
  # `Webhooks::WhatsappEventsJob` then discarded every inbound webhook for it: a number was dead for hours while
  # Meta kept delivering, nine webhooks in and no conversations out. So it is best effort here, the same way the
  # phone registration already is, and refused by the same accounts for the same reason.
  #
  # Answers whether that optional half landed. The required one raises when it fails, so reaching
  # the answer at all means Meta is delivering; `false` means it is delivering to whatever the
  # app's own callback says, which on an installation that points elsewhere is the difference
  # between a working inbox and a quiet one. The caller is what turns that answer into something
  # the operator can see.
  def subscribe_phone_number_webhook(waba_id, phone_number_id, callback_url, verify_token, subscribed_fields: nil)
    subscribe_app_to_waba(waba_id, subscribed_fields: subscribed_fields || WEBHOOK_DEFAULT_FIELDS)

    callback_override_applied?(phone_number_id, callback_url, verify_token)
  end

  def subscribe_app_to_waba(waba_id, subscribed_fields: WEBHOOK_DEFAULT_FIELDS)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/subscribed_apps",
      **GRAPH_REQUEST_OPTIONS,
      headers: request_headers,
      body: { subscribed_fields: subscribed_fields }.to_json
    )

    handle_response(response, 'App subscription to WABA failed')
  end

  def override_phone_number_callback(phone_number_id, callback_url, verify_token)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      **GRAPH_REQUEST_OPTIONS,
      headers: request_headers,
      body: {
        webhook_configuration: {
          override_callback_uri: callback_url,
          verify_token: verify_token
        }
      }.to_json
    )

    handle_response(response, 'Phone number webhook callback override failed')
  end

  def clear_phone_number_callback_override(phone_number_id)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      **GRAPH_REQUEST_OPTIONS,
      headers: request_headers,
      body: {
        webhook_configuration: {
          override_callback_uri: ''
        }
      }.to_json
    )

    handle_response(response, 'Phone number webhook callback clear failed')
  end

  # Fully removes this app's WABA subscription (last inbox deleted) so Meta stops delivering webhooks.
  def unsubscribe_app_from_waba(waba_id)
    response = HTTParty.delete(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/subscribed_apps",
      **GRAPH_REQUEST_OPTIONS,
      headers: request_headers
    )

    handle_response(response, 'WABA app unsubscription failed')
  end

  private

  # Any failure at all, and deliberately not a status or a message: the same refusal arrives as a
  # 403 carrying Meta's code 200, as a plain 500, and as a connection that closes with nothing to
  # read. A guard that recognizes one shape leaves the other two killing the channel.
  #
  # The line names the call and the number because it is what a diagnosis starts from: the answer
  # below reaches the operator as a sentence, and the log is where you find which number and which
  # URL were refused.
  #
  # The rescue is the whole definition of "not applied": a refusal is the only way this call does
  # not land, and reading the body for a shape would put the three of them back in play.
  def callback_override_applied?(phone_number_id, callback_url, verify_token)
    override_phone_number_callback(phone_number_id, callback_url, verify_token)
    true
  rescue StandardError => e
    Rails.logger.warn('[WHATSAPP] Phone number webhook callback override failed but continuing ' \
                      "(phone_number_id #{phone_number_id}, #{callback_url}): #{e.message}")
    false
  end

  def request_headers
    {
      'Authorization' => "Bearer #{@access_token}",
      'Content-Type' => 'application/json'
    }
  end

  def build_app_access_token
    app_id = GlobalConfigService.load('WHATSAPP_APP_ID', '')
    app_secret = GlobalConfigService.load('WHATSAPP_APP_SECRET', '')
    "#{app_id}|#{app_secret}"
  end

  # The message is unchanged, because it is what reaches the operator through the register-webhook
  # endpoint. What is new is that the error also carries Meta's code, which is the only thing that
  # separates "this token is no good" from "this request was refused" for whoever rescues it.
  def handle_response(response, error_message)
    raise Whatsapp::ApiError.from_response(response, message: "#{error_message}: #{response.body}") unless response.success?

    response.parsed_response
  end
end
