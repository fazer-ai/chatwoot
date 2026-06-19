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
    # so we can tell when Meta's "method type: X" rejection is actually
    # a malformed-token issue dressed up as a method rejection. NEVER
    # logs the token value, just its length and first 4 chars.
    Rails.logger.info(
      "[instagram] long-lived exchange: token_present=#{short_lived_token.present?} " \
      "token_length=#{short_lived_token.to_s.length} " \
      "token_prefix=#{short_lived_token.to_s[0, 4]}"
    )

    # Meta keeps flipping the accepted HTTP method on this endpoint.
    # Symptom: `IGApiException code 100: "Unsupported request - method
    # type: <get|post>"`. Try one method, and if Meta rejects with that
    # specific error, automatically retry with the other. Avoids having
    # to redeploy every time Meta swings.
    attempt_token_exchange_with_fallback(endpoint, params)
  end

  def attempt_token_exchange_with_fallback(endpoint, params)
    make_api_request(endpoint, params, 'Failed to exchange token', method: :post)
  rescue RuntimeError => e
    raise unless /method type:\s*post/i.match?(e.message)

    Rails.logger.warn('[instagram] POST rejected by Meta, retrying with GET')
    make_api_request(endpoint, params, 'Failed to exchange token', method: :get)
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

  # Same flip-resilience pattern as `attempt_token_exchange_with_fallback`:
  # Meta keeps returning the cryptic "method type: <get|post>" on Instagram
  # endpoints. Try POST first (matches what works on the token exchange),
  # fall back to GET if Meta rejects POST with that specific error.
  def attempt_user_details_with_fallback(endpoint, params)
    make_api_request(endpoint, params, 'Failed to fetch Instagram user details', method: :post)
  rescue RuntimeError => e
    raise unless /method type:\s*post/i.match?(e.message)

    Rails.logger.warn('[instagram] /me POST rejected by Meta, retrying with GET')
    make_api_request(endpoint, params, 'Failed to fetch Instagram user details', method: :get)
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
