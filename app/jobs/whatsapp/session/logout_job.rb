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
    channel.provider_service.logout
  rescue Whatsapp::Session::Errors::ProviderUnavailable, Whatsapp::Session::Errors::RateLimited
    raise
  rescue Whatsapp::Session::Errors::Error => e
    # Nothing a retry fixes: the session is already gone, or the backend cannot be asked.
    Rails.logger.warn("[WHATSAPP SESSION] logout failed for inbox #{channel.inbox&.id}: #{e.message}")
  end
end
