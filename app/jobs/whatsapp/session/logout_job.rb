# Drops a session Chatwoot refuses to keep, retrying until the provider takes the order.
#
# The one caller is the wrong-number rejection, where a swallowed failure is the worst
# outcome available: the state is already written, so the handler will report every
# repeat of it as unchanged and never reach the logout again, and the wrong WhatsApp
# account stays connected with nobody asking it to stop.
class Whatsapp::Session::LogoutJob < ApplicationJob
  queue_as :high

  retry_on Whatsapp::Session::Errors::ProviderUnavailable, wait: :polynomially_longer, attempts: 6
  retry_on Whatsapp::Session::Errors::RateLimited, wait: :polynomially_longer, attempts: 6

  def perform(channel)
    # Re-read, because a retry of this job can run minutes after the rejection that
    # queued it: the administrator may have corrected the number and paired again, or
    # converted the inbox altogether, and logging out then kills the session that
    # replaced the one this was sent to remove. The quarantine is the whole reason this
    # job exists, so its absence is reason enough not to run.
    #
    # A check, not a fence, and it cannot be one here: a retry that passes it and is still
    # inside the provider call when the operator reconnects ends the new session anyway.
    # Closing that needs a logout naming the session it means to end, and `session.logout`
    # addresses whichever session the inbox holds now. The operator's own sequence does
    # not depend on it: `Facade#setup_channel_provider` ends the wrong account inline
    # before connecting, and this job then finds no quarantine and stands down.
    return unless Whatsapp::Session::ConnectionStateWriter.disowned?(channel.reload)

    channel.session_backend.logout
  rescue Whatsapp::Session::Errors::ProviderUnavailable, Whatsapp::Session::Errors::RateLimited
    raise
  rescue Whatsapp::Session::Errors::Error => e
    # Nothing a retry fixes: the session is already gone, or the backend cannot be asked.
    Rails.logger.warn("[WHATSAPP SESSION] logout failed for inbox #{channel.inbox&.id}: #{e.message}")
  end
end
