# Runs one inbound event through the dispatcher.
#
# This is the path for providers that deliver over HTTP (a webhook translates its
# payload into canonical events and enqueues one job per event). The connector's own
# events are dispatched inline by the stream consumer, which is what preserves their
# order.
#
# UNORDERED, ON PURPOSE, FOR NOW (fazer-ai/chatwoot#373). One job per event means two
# events of the same chat can run in either order, so a revoke, an edit or a reaction
# can execute before the `message.received` that stores its target, find nothing, and be
# dropped for good. The guard belongs here, and what it can be depends on whether the
# provider's webhook carries a sequence or a usable timestamp: that is captured from a
# live instance in the Uazapi slice, and the mechanism is chosen then.
#
# The same issue covers the other half, redelivery: nothing claims `Event#id` before the
# dispatcher runs a handler, so a stream replay or a webhook retry writes a second
# activity row for a group change and re-fires `PROVIDER_EVENT_RECEIVED`. One mechanism
# (a per-session cursor, or an event-id claim) answers both, which is why they are
# decided together. Do not delete this note without closing the issue.
class Whatsapp::Session::EventJob < ApplicationJob
  queue_as :high

  # Another worker holds the chat or the message: retried rather than waited on, so a
  # Sidekiq thread is never parked on Redis. The backoff has to outlast a marker left
  # behind by a killed worker, which is why it grows instead of staying at two seconds.
  retry_on Whatsapp::Session::Inbound::Locks::Busy, wait: :polynomially_longer, attempts: 6

  # `frame` is a decoded event frame (Model::Event#to_frame).
  def perform(channel, frame)
    event = Whatsapp::Session::Model::Event.from_frame(frame)
    Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)
  rescue Whatsapp::Session::Errors::InvalidEvent, Whatsapp::Session::Errors::InvalidPayload => e
    # A payload this version cannot read is a provider or contract problem, not
    # something a retry fixes.
    Rails.logger.error("[WHATSAPP SESSION] invalid event on inbox #{channel.inbox&.id}: #{e.message}")
  end
end
