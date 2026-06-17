class Channels::Whatsapp::BaileysConnectionCheckJob < ApplicationJob
  queue_as :low

  def perform(whatsapp_channel)
    whatsapp_channel.setup_channel_provider
    refresh_reachout_time_lock(whatsapp_channel)
    refresh_new_chat_cap(whatsapp_channel)
  end

  private

  # Best-effort: a failed time-lock fetch must not abort the connection check (which also
  # re-arms the session). nil means "unknown" (404/error) — skip so we never clear a banner
  # that a webhook push legitimately set; the banner then falls back to push-driven state.
  def refresh_reachout_time_lock(whatsapp_channel)
    lock = whatsapp_channel.provider_service.fetch_reachout_timelock
    whatsapp_channel.update_reachout_time_lock!(lock) unless lock.nil?
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP][BAILEYS] reachout timelock refresh failed for ##{whatsapp_channel.id}: #{e.message}")
  end

  # Same best-effort contract as refresh_reachout_time_lock: nil (404/error) leaves the last known
  # cap untouched so a transient blip doesn't clear a legitimately-set banner.
  def refresh_new_chat_cap(whatsapp_channel)
    cap = whatsapp_channel.provider_service.fetch_new_chat_cap
    whatsapp_channel.update_new_chat_cap!(cap) unless cap.nil?
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP][BAILEYS] new-chat cap refresh failed for ##{whatsapp_channel.id}: #{e.message}")
  end
end
