# Periodic health read for a session inbox whose provider has to be asked.
#
# Two things only a poll can learn: that the session died without the provider saying so
# (a hosted instance can be disconnected from its own dashboard, or simply stop), and the
# account limits, which are never pushed. Both are read, never re-connected: re-arming a
# session that is up is the connector's job on its own side, and asking a hosted provider
# to connect every five minutes would re-register the webhook for nothing.
class Whatsapp::Session::ConnectionCheckJob < ApplicationJob
  queue_as :low

  def perform(channel)
    return unless channel.session_provider?

    backend = channel.session_backend
    return unless backend.class.state_polling?

    refresh_state(channel, backend)
    refresh_limits(channel, backend)
  end

  private

  # Fenced to the provider this job was scheduled for: an inbox converted while the job
  # sat in the queue has an empty connection record belonging to somebody else.
  def refresh_state(channel, backend)
    Whatsapp::Session::ConnectionStateWriter.new(channel).apply(backend.fetch_connection_state, provider: channel.provider)
  rescue Whatsapp::Session::Errors::Error => e
    # A provider that cannot be reached is not the same as a session that closed, and
    # writing `close` over a healthy connection because of one failed request would show
    # the operator an outage that is not there. The next cycle asks again.
    Rails.logger.warn("[WHATSAPP SESSION] connection check failed for inbox ##{channel.inbox&.id}: #{e.message}")
  end

  # Best effort, and separately rescued: a provider that answers the status but not the
  # limits must not cost the status read. A missing value means "unknown" and leaves the
  # last one in place, so a blip never clears a banner that is legitimately up.
  def refresh_limits(channel, backend)
    limits = backend.fetch_account_limits || {}
    channel.update_reachout_time_lock!(limits['reachout_time_lock'])
    channel.update_new_chat_cap!(limits['new_chat_cap'])
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.warn("[WHATSAPP SESSION] account limits refresh failed for inbox ##{channel.inbox&.id}: #{e.message}")
  end
end
