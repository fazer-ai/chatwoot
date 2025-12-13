# frozen_string_literal: true

module FazerAi::Internal::CheckNewVersionsJob
  def perform
    super
    update_subscription_config
    reconcile_subscription
  end

  private

  def sync_with_hub
    FazerAiHub.sync_subscription || {}
  end

  def update_subscription_config
    return if @instance_info.blank?

    token = @instance_info['subscription_token']
    unless token.present? && FazerAi::SubscriptionToken.valid?(token)
      Rails.logger.warn('[fazer.ai] Received invalid or missing subscription token from hub')
      return
    end

    update_protected_config('FAZER_AI_SUBSCRIPTION_TOKEN', token)
    update_protected_config('FAZER_AI_SUBSCRIPTION_VERIFIED_AT', Time.current.iso8601)
    FazerAiHub.clear_cache!
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

  def reconcile_subscription
    FazerAi::ReconcileSubscriptionService.new.perform
  end
end
