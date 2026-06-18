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

    # Meta has flipped the accepted HTTP method on this endpoint twice
    # in two days:
    #   - up to mid-Jun/2026: GET worked (then started rejecting with
    #     `IGApiException code 100: "Unsupported request - method type: get"`)
    #   - 16-Jun-2026: we switched to POST (v1.27.1)
    #   - 18-Jun-2026: Meta reverted; POST now returns the symmetric
    #     `"Unsupported request - method type: post"`.
    # Back to GET. If Meta flips again, the `IGApiException code 100`
    # message will literally say which method is "unsupported" — read the
    # log line emitted by `make_api_request` and flip accordingly.
    make_api_request(endpoint, params, 'Failed to exchange token', method: :get)
  end

  def fetch_instagram_user_details(access_token)
    endpoint = 'https://graph.instagram.com/v22.0/me'
    params = {
      fields: 'id,username,user_id,name,profile_picture_url,account_type',
      access_token: access_token
    }

    make_api_request(endpoint, params, 'Failed to fetch Instagram user details')
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
