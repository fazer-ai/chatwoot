# The history half of the facade: asking a chat for what came before, and whether this
# inbox asked for it at all.
#
# Split out for the same reason the group half is: the facade is at the length the project
# allows, and this is its own subject.
module Whatsapp::Session::Facade::History
  # Asks a chat for the history behind it. Nothing here waits for it: the provider
  # acknowledges the request and the messages arrive as `history.sync` events, if the
  # phone is awake to answer at all, which is why the caller is told the request went out
  # rather than what it produced.
  # `before` is the stored message to page backwards from, or nil to start from the oldest
  # the provider knows. A message rather than an id: the anchor needs its timestamp and its
  # direction too, and the row is the one place that has all three together.
  def request_history(contact, count: nil, before: nil)
    raise Whatsapp::Session::Errors::NotSupported, I18n.t('errors.inboxes.channel.history_sync_unsupported') unless capability?('history_sync')

    backend.request_history(
      model::Commands::HistoryRequest.new(
        chat: model::Address.for_contact(contact), count: count,
        before: model::Commands::HistoryAnchor.for_message(before)
      )
    )
    true
  end

  # Whether this inbox asked for the history the phone already has. Off unless the
  # operator turned it on: the phone answers with everything it has, and an inbox that
  # never asked should not have a year of somebody else's conversations imported into it
  # on the first connect.
  #
  # Public because it also gates the on-demand backfill. The answer to a request arrives
  # on the webhook, and the webhook only carries history for an inbox that subscribed to
  # it, so with this off the request would go out and the reply would be dropped.
  def history_sync?
    capability?('history_sync') && ActiveModel::Type::Boolean.new.cast(channel.provider_config&.dig('history_sync')).present?
  end
end
