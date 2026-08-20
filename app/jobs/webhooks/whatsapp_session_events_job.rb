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
# The retry replays the whole body, so anything a translator emits alongside a deferrable
# event has to survive running twice. Only a bulk revoke does that today, and its handler
# is a no-op on a message it has already flagged.
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

  # `payload` is the provider's webhook body, as it arrived, and `instance` names the
  # provider instance it was authenticated against, which the dispatcher fences every
  # event against: the token that authenticated the body is stripped before it is
  # enqueued, and two instances of a hosted provider share a base URL, so without it the
  # previous instance's messages are filed under the new one.
  #
  # Optional because a caller can have nothing to name, and a fence on the shape of the
  # call would be no fence at all. Every enqueue in this build names one.
  def perform(channel, payload, instance = nil)
    translator = Whatsapp::Session::Registry.translator_for(channel)
    return if translator.nil?

    deferred = dispatch(channel, translator.new(channel, payload).perform, instance)
    return if deferred.empty?

    raise Whatsapp::Session::Errors::EventOutOfOrder,
          "#{deferred.map(&:type).uniq.join(', ')} arrived before the messages they refer to"
  rescue Whatsapp::Session::Errors::InvalidEvent, Whatsapp::Session::Errors::InvalidPayload => e
    # A body this version cannot read is a provider or contract problem, not something a
    # retry fixes.
    Rails.logger.error("[WHATSAPP SESSION] invalid webhook on inbox ##{channel.inbox&.id}: #{e.message}")
  end

  private

  # Every event first, and only then the wait. Raising on the first one that has to wait
  # would leave the rest of a bulk deletion undispatched, and every retry would stop at
  # the same missing message: the ids after it would never be deleted at all.
  def dispatch(channel, events, instance)
    events.select do |event|
      Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event, instance: instance) == :deferred
    end
  end
end
