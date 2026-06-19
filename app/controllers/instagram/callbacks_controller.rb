class Instagram::CallbacksController < ApplicationController
  include InstagramConcern
  include Instagram::IntegrationHelper

  def show
    # Check if Instagram redirected with an error (user canceled authorization)
    # See: https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#canceled-authorization
    if params[:error].present?
      handle_authorization_error
      return
    end

    process_successful_authorization
  rescue StandardError => e
    handle_error(e)
  end

  private

  # Process the authorization code and create inbox
  def process_successful_authorization
    @response = instagram_client.auth_code.get_token(
      oauth_code,
      redirect_uri: "#{base_url}/#{provider_name}/callback",
      grant_type: 'authorization_code'
    )

    log_short_lived_response(@response)
    @long_lived_token_response = resolve_long_lived_token(@response)
    inbox, already_exists = find_or_create_inbox

    if already_exists
      redirect_to app_instagram_inbox_settings_url(account_id: account_id, inbox_id: inbox.id)
    else
      redirect_to app_instagram_inbox_agents_url(account_id: account_id, inbox_id: inbox.id)
    end
  end

  # Handle all errors that might occur during authorization
  # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#sample-rejected-response
  def handle_error(error)
    Rails.logger.error("Instagram Channel creation Error: #{error.message}")
    ChatwootExceptionTracker.new(error).capture_exception

    error_info = extract_error_info(error)
    redirect_to_error_page(error_info)
  end

  # Extract error details from the exception
  def extract_error_info(error)
    if error.is_a?(OAuth2::Error)
      begin
        # Instagram returns JSON error response which we parse to extract error details
        JSON.parse(error.message)
      rescue JSON::ParseError
        # Fall back to a generic OAuth error if JSON parsing fails
        { 'error_type' => 'OAuthException', 'code' => 400, 'error_message' => error.message }
      end
    else
      # For other unexpected errors
      { 'error_type' => error.class.name, 'code' => 500, 'error_message' => error.message }
    end
  end

  # Handles the case when a user denies permissions or cancels the authorization flow
  # Error parameters are documented at:
  # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#canceled-authorization
  def handle_authorization_error
    error_info = {
      'error_type' => params[:error] || 'authorization_error',
      'code' => 400,
      'error_message' => params[:error_description] || 'Authorization was denied'
    }

    Rails.logger.error("Instagram Authorization Error: #{error_info['error_message']}")
    redirect_to_error_page(error_info)
  end

  # Centralized method to redirect to error page with appropriate parameters
  # This ensures consistent error handling across different error scenarios
  # Frontend will handle the error page based on the error_type
  def redirect_to_error_page(error_info)
    redirect_to app_new_instagram_inbox_url(
      account_id: account_id,
      error_type: error_info['error_type'],
      code: error_info['code'],
      error_message: error_info['error_message']
    )
  end

  def find_or_create_inbox
    # `user_id` already comes back from Meta on the OAuth short-lived
    # response (`@response.params['user_id']`). We don't need /me to
    # create the channel — `/me` has been rejecting both POST and GET
    # for IGAA tokens regardless of fallback. Use the OAuth user_id
    # directly and best-effort the display name via the user-id-keyed
    # endpoint, falling back to a placeholder if Meta blocks that too.
    user_id = @response.params['user_id'].to_s
    raise 'Instagram OAuth response missing user_id' if user_id.blank?

    user_details = build_user_details(user_id)
    channel_instagram, channel_existed = persist_channel(user_id, user_details)

    Rails.logger.info(
      "[instagram] inbox ready: channel_id=#{channel_instagram.id} inbox_id=#{channel_instagram.inbox.id} " \
      "expires_at=#{channel_instagram.expires_at}"
    )

    [channel_instagram.inbox, channel_existed]
  end

  def persist_channel(user_id, user_details)
    channel_instagram = find_channel_by_instagram_id(user_id)
    channel_existed = channel_instagram.present?

    Rails.logger.info(
      "[instagram] resolved channel: existing=#{channel_existed} " \
      "account_id=#{account.id} instagram_user_id=#{user_id}"
    )

    if channel_instagram
      update_channel(channel_instagram, user_details)
    else
      channel_instagram = create_channel_with_inbox(user_details)
    end

    # reauthorize channel; only triggers on successful auth and refreshes
    # the cache keys for the associated inbox.
    channel_instagram.reauthorized!
    [channel_instagram, channel_existed]
  end

  # Best-effort name fetch — tries the user-id-keyed endpoint (NOT /me)
  # because that's the one that's been working when /me wasn't. If even
  # that fails we still ship the inbox with a placeholder name; the
  # operator can rename it from settings.
  def build_user_details(user_id)
    username = fetch_username_safely(user_id)
    {
      'user_id' => user_id,
      'username' => username.presence || "Instagram (#{user_id})"
    }
  end

  def fetch_username_safely(user_id)
    endpoint = "https://graph.instagram.com/#{Channel::Instagram.api_version}/#{user_id}"
    params = { fields: 'username', access_token: @long_lived_token_response['access_token'] }

    response = HTTParty.get(endpoint, query: params, headers: { 'Accept' => 'application/json' })
    return nil unless response.success?

    parsed = JSON.parse(response.body)
    Rails.logger.info("[instagram] /{user_id} fetch ok username=#{parsed['username']}")
    parsed['username']
  rescue StandardError => e
    Rails.logger.warn("[instagram] /{user_id} fetch failed for user_id=#{user_id}: #{e.message}")
    nil
  end

  def find_channel_by_instagram_id(instagram_id)
    Channel::Instagram.find_by(instagram_id: instagram_id, account: account)
  end

  def update_channel(channel_instagram, user_details)
    expires_at = Time.current + @long_lived_token_response['expires_in'].seconds

    channel_instagram.update!(
      access_token: @long_lived_token_response['access_token'],
      expires_at: expires_at
    )

    # Update inbox name if username changed
    channel_instagram.inbox.update!(name: user_details['username'])
    channel_instagram
  end

  def create_channel_with_inbox(user_details)
    ActiveRecord::Base.transaction do
      expires_at = Time.current + @long_lived_token_response['expires_in'].seconds

      channel_instagram = Channel::Instagram.create!(
        access_token: @long_lived_token_response['access_token'],
        instagram_id: user_details['user_id'].to_s,
        account: account,
        expires_at: expires_at
      )

      account.inboxes.create!(
        account: account,
        channel: channel_instagram,
        name: user_details['username']
      )

      channel_instagram
    end
  end

  def account_id
    return unless params[:state]

    verify_instagram_token(params[:state])
  end

  def oauth_code
    params[:code]
  end

  def account
    @account ||= Account.find(account_id)
  end

  def provider_name
    'instagram'
  end

  # Diagnostic: capture the shape of what Instagram returned for the
  # short-lived token exchange. Helps tell apart Meta-side rejections
  # from us-passing-something-weird-along to the long-lived exchange.
  def log_short_lived_response(response)
    Rails.logger.info(
      "[instagram] short-lived response: token_class=#{response.class.name} " \
      "token_present=#{response.token.present?} " \
      "token_length=#{response.token.to_s.length} " \
      "expires_in=#{response.expires_in.inspect} " \
      "params_keys=#{response.params.keys.inspect}"
    )
  end

  # In the Instagram Business Login flow on Graph API v23+ Meta returns
  # a long-lived (60-day) token directly from the code exchange — the
  # `expires_in` is either missing (no exchange needed) or already >> 1h.
  # In that case calling `ig_exchange_token` produces a confusing
  # "method type: <get|post>" error because there's nothing to exchange.
  # Only fall back to the legacy exchange when Meta explicitly tagged
  # the token as short-lived (expires_in <= 1h).
  SHORT_LIVED_THRESHOLD_SECONDS = 1.hour.to_i

  def resolve_long_lived_token(response)
    if response.expires_in.is_a?(Integer) && response.expires_in <= SHORT_LIVED_THRESHOLD_SECONDS
      Rails.logger.info('[instagram] short-lived token detected, exchanging for long-lived')
      exchange_for_long_lived_token(response.token)
    else
      Rails.logger.info('[instagram] token already long-lived (or expires_in missing), skipping legacy exchange')
      {
        'access_token' => response.token,
        'expires_in' => response.expires_in || 60.days.to_i
      }
    end
  end
end
