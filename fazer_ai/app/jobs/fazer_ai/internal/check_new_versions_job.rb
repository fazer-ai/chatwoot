# frozen_string_literal: true

module FazerAi::Internal::CheckNewVersionsJob
  OUT_OF_SYNC_THRESHOLD = 3.days

  def perform(jitter_applied: false)
    super
    return unless jitter_applied || Rails.env.test?

    sync_subscription_with_hub
    reconcile_subscription
  end

  private

  def sync_with_hub
    chatwoot_response = ChatwootHub.sync_with_hub || {}
    fazer_ai_response = FazerAiHub.sync_subscription || {}
    # NOTE: FazerAiHub takes precedence for overlapping keys
    chatwoot_response.merge(fazer_ai_response)
  end

  def sync_subscription_with_hub
    if @instance_info.blank?
      handle_sync_failure
      return
    end

    token = @instance_info['subscription_token']
    if token.blank?
      handle_inactive_subscription
      return
    end

    process_subscription_token(token)
  end

  def process_subscription_token(token)
    unless FazerAi::SubscriptionToken.valid?(token)
      Rails.logger.warn('[fazer.ai] Received invalid subscription token from hub')
      handle_sync_failure
      return
    end

    payload = FazerAi::SubscriptionToken.verify(token)
    if payload && payload['status'] == 'inactive'
      handle_inactive_subscription
      return
    end

    update_subscription_token(token)
  end

  def handle_sync_failure
    Rails.logger.warn('[fazer.ai] Hub sync failed - could not reach fazer.ai hub')
    update_protected_config('FAZER_AI_SUBSCRIPTION_SYNC_ERROR', Time.current.iso8601)

    auto_deactivate_if_stale
  end

  def handle_inactive_subscription
    Rails.logger.info('[fazer.ai] Subscription is inactive - deactivating')
    clear_subscription_token
    update_protected_config('FAZER_AI_SUBSCRIPTION_VERIFIED_AT', Time.current.iso8601)
    clear_protected_config('FAZER_AI_SUBSCRIPTION_SYNC_ERROR')
    FazerAiHub.clear_cache!
  end

  def update_subscription_token(token)
    update_protected_config('FAZER_AI_SUBSCRIPTION_TOKEN', token)
    update_protected_config('FAZER_AI_SUBSCRIPTION_VERIFIED_AT', Time.current.iso8601)
    clear_protected_config('FAZER_AI_SUBSCRIPTION_SYNC_ERROR')
    FazerAiHub.clear_cache!
  end

  def clear_subscription_token
    clear_protected_config('FAZER_AI_SUBSCRIPTION_TOKEN')
  end

  def clear_subscription_configs
    clear_protected_config('FAZER_AI_SUBSCRIPTION_TOKEN')
    clear_protected_config('FAZER_AI_SUBSCRIPTION_VERIFIED_AT')
    clear_protected_config('FAZER_AI_SUBSCRIPTION_SYNC_ERROR')
  end

  def auto_deactivate_if_stale
    last_verified = InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT')&.value
    return if last_verified.blank?

    last_verified_at = Time.zone.parse(last_verified)
    return if last_verified_at.nil?

    return unless last_verified_at < OUT_OF_SYNC_THRESHOLD.ago

    Rails.logger.warn("[fazer.ai] Subscription out of sync for more than #{OUT_OF_SYNC_THRESHOLD.inspect} - auto-deactivating")
    handle_inactive_subscription
  end

  def update_protected_config(key, value)
    return if value.nil?

    Current.set(fazer_ai_trusted_subscription_update: true) do
      config = InstallationConfig.find_or_initialize_by(name: key)
      config.value = value
      config.locked = true
      config.save!
    end
  end

  def clear_protected_config(key)
    Current.set(fazer_ai_trusted_subscription_update: true) do
      InstallationConfig.find_by(name: key)&.destroy
    end
  end

  def reconcile_subscription
    FazerAi::ReconcileSubscriptionService.new.perform
  end
end
