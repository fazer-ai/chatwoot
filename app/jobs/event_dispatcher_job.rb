class EventDispatcherJob < ApplicationJob
  # Most events here are agent-facing (assignment changes, notifications,
  # reporting fanout, automation rules, mentions) and need the priority
  # headroom of `:critical`. The exception we deliberately demote is
  # `provider.event_received`: it fires for EVERY raw event from a
  # WhatsApp provider (notably the constant Baileys `presence.update`
  # flood) and is only consumed by `WebhookListener` to mirror the
  # payload to an account's external webhooks. Its delivery deadline is
  # whatever the operator's downstream URL can absorb, not the UI
  # roundtrip. Letting it ride `:critical` crowded out actual UI
  # broadcasts and notifications during busy hours.
  LOW_PRIORITY_EVENTS = ['provider.event_received'].freeze

  queue_as do
    LOW_PRIORITY_EVENTS.include?(arguments.first) ? :low : :critical
  end

  def perform(event_name, timestamp, data)
    Rails.configuration.dispatcher.async_dispatcher.publish_event(event_name, timestamp, data)
  end
end
