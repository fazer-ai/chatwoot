# One webhook from a session provider that delivers over HTTP, translated and dispatched.
#
# The controller does nothing but authenticate and enqueue, so a translation this build
# cannot do never turns into a non-2xx the provider would keep retrying.
#
# ORDERING. The connector shards a session's events onto one thread and they arrive in
# order by construction; a webhook has no such guarantee, and there is nothing in the
# Uazapi payloads to rebuild one from (fazer-ai/chatwoot#373). Messages carry a
# millisecond timestamp, receipts carry seconds in one shape and an ISO string in
# another, and presence carries none at all, so a per-chat cursor has nothing monotonic
# to compare. What is left is to wait: a handler whose target message is not stored yet
# answers `:deferred` and this job retries, which turns an ordering problem into a
# bounded delay. A revoke or an edit for a message Chatwoot never had (one from before
# the inbox was connected) costs that ladder and is then dropped.
#
# Which is also why a translator answers with at most one event per body: the retry
# replays the whole job, so an event dispatched before the one that deferred would run
# twice. Every shape in the capture is one event, and a spec holds the translator to it.
class Webhooks::WhatsappSessionEventsJob < ApplicationJob
  queue_as :high

  # Another worker holds the chat or the message: retried rather than waited on, so a
  # Sidekiq thread is never parked on Redis.
  retry_on Whatsapp::Session::Inbound::Locks::Busy, wait: :polynomially_longer, attempts: 6

  # The wait for a message that has not arrived yet. Bounded, and dropped at the end
  # rather than re-raised: the target of a revoke or an edit can legitimately be a
  # message this inbox never stored, and that is not a failure worth a dead job.
  retry_on Whatsapp::Session::Errors::EventOutOfOrder, wait: :polynomially_longer, attempts: 5 do |job, error|
    Rails.logger.warn("[WHATSAPP SESSION] giving up on an out-of-order event for inbox ##{job.arguments.first&.id}: #{error.message}")
  end

  # `payload` is the provider's webhook body, as it arrived.
  def perform(channel, payload)
    translator = Whatsapp::Session::Registry.translator_for(channel)
    return if translator.nil?

    translator.new(channel, payload).perform.each { |event| dispatch(channel, event) }
  rescue Whatsapp::Session::Errors::InvalidEvent, Whatsapp::Session::Errors::InvalidPayload => e
    # A body this version cannot read is a provider or contract problem, not something a
    # retry fixes.
    Rails.logger.error("[WHATSAPP SESSION] invalid webhook on inbox ##{channel.inbox&.id}: #{e.message}")
  end

  private

  def dispatch(channel, event)
    result = Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)
    return unless result == :deferred

    raise Whatsapp::Session::Errors::EventOutOfOrder, "#{event.type} arrived before the message it refers to"
  end
end
