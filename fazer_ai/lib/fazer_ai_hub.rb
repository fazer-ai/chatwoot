# frozen_string_literal: true

class FazerAiHub
  BASE_URL = ENV.fetch('FAZER_AI_HUB_URL', 'https://app.fazer.ai')
  PING_URL = "#{BASE_URL}/api/ping".freeze
  BILLING_URL = "#{BASE_URL}/api/billing".freeze

  class << self
    def installation_identifier
      ChatwootHub.installation_identifier
    end

    def billing_url
      "#{BILLING_URL}?installation_identifier=#{installation_identifier}"
    end

    def subscription_status
      if out_of_sync? && subscription_token.present?
        last_status = last_known_subscription_status
        return last_status if last_status.present?
      end

      return 'inactive' unless subscription_token_valid?

      cached_subscription_data[:status] || 'inactive'
    end

    def kanban_account_limit
      return nil unless subscription_token_valid?

      feature_limit('kanban', 'account_limit')
    end

    def feature_limit(feature_name, limit_key)
      feature_config = features.with_indifferent_access[feature_name]
      return nil unless feature_config.is_a?(Hash)

      config = feature_config.with_indifferent_access
      return nil unless config.key?(limit_key)

      config[limit_key].to_i
    end

    def instance_type
      return nil unless subscription_token_valid?

      cached_subscription_data[:instance_type]
    end

    def enabled_features
      return [] unless subscription_token_valid?

      features.keys
    end

    def features
      return {} unless subscription_token_valid?

      cached_subscription_data[:features] || {}
    end

    def feature_enabled?(feature_name)
      enabled_features.include?(feature_name)
    end

    def synced?
      subscription_token.present? && subscription_verified_recently?
    end

    def never_synced?
      last_synced_at.nil?
    end

    def out_of_sync?
      sync_error_at.present?
    end

    def sync_error_at
      error_at = InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_SYNC_ERROR')&.value
      return nil if error_at.blank?

      Time.zone.parse(error_at)
    rescue ArgumentError
      nil
    end

    def last_synced_at
      verified_at = InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT')&.value
      return nil if verified_at.blank?

      Time.zone.parse(verified_at)
    rescue ArgumentError
      nil
    end

    def subscription_active?
      %w[active past_due trialing].include?(subscription_status)
    end

    def subscription_past_due?
      subscription_status == 'past_due'
    end

    def subscription_canceling?
      return false unless subscription_token_valid?

      cached_subscription_data[:cancel_at_period_end] == true
    end

    def subscription_period_end
      return nil unless subscription_token_valid?

      cached_subscription_data[:current_period_end]
    end

    def instance_config
      {
        installation_identifier: installation_identifier,
        installation_version: Chatwoot.config[:version],
        installation_host: URI.parse(ENV.fetch('FRONTEND_URL', '')).host,
        instance_type: 'chatwoot',
        session_id: FazerAi::Session.session_id,
        feature_usage: feature_usage
      }
    end

    def feature_usage
      {
        kanban: {
          account_limit: kanban_enabled_accounts_count
        }
      }
    end

    def kanban_enabled_accounts_count
      Account.where('feature_flags & ? != 0', Featurable.feature_flag_value('kanban')).count
    end

    def sync_subscription
      response = HTTParty.post(
        PING_URL,
        body: instance_config.to_json,
        headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
        timeout: 10
      )

      return { 'inactive' => true } if response.code == 403

      return nil unless response.success?

      JSON.parse(response.body)
    rescue StandardError => e
      Rails.logger.error "[fazer.ai] Hub sync error: #{e.message}"
      nil
    end

    def subscription_verified_recently?
      verified_at = InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT')&.value
      FazerAi::SubscriptionToken.verified_recently?(verified_at)
    end

    def subscription_token
      InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_TOKEN')&.value
    end

    def subscription_token_valid?
      return false unless subscription_verified_recently?

      token = subscription_token
      return false if token.blank?

      verify_subscription_token(token).present?
    end

    def verify_subscription_token(token)
      FazerAi::SubscriptionToken.verify(token)
    end

    def last_known_subscription_status
      token = subscription_token
      return nil if token.blank?

      payload = JWT.decode(token, nil, false).first
      payload['status']
    rescue JWT::DecodeError
      nil
    end

    def clear_cache!
      Current.fazer_ai_subscription_data = nil
    end

    private

    def cached_subscription_data
      return Current.fazer_ai_subscription_data if Current.fazer_ai_subscription_data.present?

      Current.fazer_ai_subscription_data = build_subscription_data
    end

    def build_subscription_data
      token = subscription_token
      return {} if token.blank?

      payload = verify_subscription_token(token)
      return {} if payload.blank?

      {
        status: payload['status'],
        instance_type: payload['instance_type'],
        features: payload['features'] || {},
        cancel_at_period_end: payload['cancel_at_period_end'] || false,
        current_period_end: payload['current_period_end']
      }
    end
  end
end
