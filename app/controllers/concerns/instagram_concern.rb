module InstagramConcern
  extend ActiveSupport::Concern

  def instagram_client
    ::OAuth2::Client.new(
      client_id,
      client_secret,
      {
        site: 'https://api.instagram.com',
        authorize_url: 'https://api.instagram.com/oauth/authorize',
        token_url: 'https://api.instagram.com/oauth/access_token',
        auth_scheme: :request_body,
        token_method: :post
      }
    )
  end

  private

  def client_id
    GlobalConfigService.load('INSTAGRAM_APP_ID', nil)
  end

  def client_secret
    GlobalConfigService.load('INSTAGRAM_APP_SECRET', nil)
  end

  def exchange_for_long_lived_token(short_lived_token)
    endpoint = 'https://graph.instagram.com/access_token'
    params = {
      grant_type: 'ig_exchange_token',
      client_secret: client_secret,
      access_token: short_lived_token,
      client_id: client_id
    }

    # Diagnostic logging — captures the shape of the short-lived token
    # so we can tell when Meta's method-swing rejection is actually a
    # malformed-token issue dressed up as a method rejection. NEVER
    # logs the token value, just its length and first 4 chars.
    Rails.logger.warn(
      "[instagram] long-lived exchange: token_present=#{short_lived_token.present?} " \
      "token_length=#{short_lived_token.to_s.length} " \
      "token_prefix=#{short_lived_token.to_s[0, 4]}"
    )

    # Meta keeps flipping the accepted HTTP method on this endpoint.
    # As of v24.0 the production answer is GET; POST returns code 100 /
    # subcode 33 with body "Unsupported post request. Object with ID
    # 'access_token' does not exist...". So try GET first; fall back to
    # POST if Meta swings again.
    attempt_token_exchange_with_fallback(endpoint, params)
  end

  def attempt_token_exchange_with_fallback(endpoint, params)
    make_api_request(endpoint, params, 'Failed to exchange token', method: :get)
  rescue RuntimeError => e
    raise unless meta_method_swing?(e.message, 'get')

    Rails.logger.warn('[instagram] /access_token GET rejected by Meta, retrying with POST')
    make_api_request(endpoint, params, 'Failed to exchange token', method: :post)
  end

  def fetch_instagram_user_details(access_token)
    endpoint = "https://graph.instagram.com/#{Channel::Instagram.api_version}/me"
    params = {
      fields: 'id,username,user_id,name,profile_picture_url,account_type',
      access_token: access_token
    }

    Rails.logger.info(
      "[instagram] /me request: endpoint=#{endpoint} token_present=#{access_token.present?} " \
      "token_length=#{access_token.to_s.length}"
    )

    result = attempt_user_details_with_fallback(endpoint, params)

    Rails.logger.info(
      "[instagram] /me response keys=#{result.keys.inspect} " \
      "user_id_present=#{result['user_id'].present?} username_present=#{result['username'].present?}"
    )

    result
  end

  # `/me` only accepts GET — that's the canonical, documented Meta API.
  # An earlier observation that "both methods fail" came from sending
  # POST first; when POST returns the cryptic 'method type' error, we
  # fell back to GET — but the response we logged was sometimes for the
  # POST attempt anyway (chained state). Try GET first now. POST stays
  # as a last-resort fallback in case Meta swings again — it has cost
  # zero when GET works.
  def attempt_user_details_with_fallback(endpoint, params)
    make_api_request(endpoint, params, 'Failed to fetch Instagram user details', method: :get)
  rescue RuntimeError => e
    raise unless meta_method_swing?(e.message, 'get')

    Rails.logger.warn('[instagram] /me GET rejected by Meta, retrying with POST')
    make_api_request(endpoint, params, 'Failed to fetch Instagram user details', method: :post)
  end

  # Recognizes the two flavors of "this HTTP method is not the one we
  # accept here" that Meta has used so far on Instagram Graph endpoints:
  #
  #   - "Unsupported request - method type: post"
  #       (older format — what the regex used to match)
  #
  #   - "Unsupported post request. Object with ID 'access_token' does not
  #      exist, cannot be loaded due to missing permissions, or does not
  #      support this operation"
  #       (current format on /access_token; same idea, different wording)
  #
  # When Meta swings the wording again, add the new variant here — the
  # alternative is silent OAuth failure across every new inbox.
  def meta_method_swing?(message, method)
    return false if message.blank?

    message.match?(/method type:\s*#{method}/i) ||
      message.match?(/unsupported #{method} request/i)
  end

  def make_api_request(endpoint, params, error_prefix, method: :get)
    response = case method
               when :post
                 HTTParty.post(endpoint, body: params, headers: { 'Accept' => 'application/json' })
               else
                 HTTParty.get(endpoint, query: params, headers: { 'Accept' => 'application/json' })
               end

    unless response.success?
      Rails.logger.error "#{error_prefix}. Status: #{response.code}, Body: #{response.body}"
      raise "#{error_prefix}: #{response.body}"
    end

    begin
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      ChatwootExceptionTracker.new(e).capture_exception
      Rails.logger.error "Invalid JSON response: #{response.body}"
      raise e
    end
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
