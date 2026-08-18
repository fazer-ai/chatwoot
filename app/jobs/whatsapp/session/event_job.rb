# Runs one inbound event through the dispatcher.
#
# This is the path for providers that deliver over HTTP (a webhook translates its
# payload into canonical events and enqueues one job per event). The connector's own
# events are dispatched inline by the stream consumer, which is what preserves their
# order.
class Whatsapp::Session::EventJob < ApplicationJob
  queue_as :high

  # Another worker holds the chat: retried rather than waited on, so a Sidekiq thread
  # is never parked on Redis.
  retry_on Whatsapp::Session::Inbound::Locks::Busy, wait: 2.seconds, attempts: 5

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
