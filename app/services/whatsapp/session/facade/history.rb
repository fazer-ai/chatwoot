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
  #
  # A backend that can only page backwards from a message gets the oldest one this inbox
  # holds for the contact, across every thread it opened, which is where the phone's copy
  # and ours stop overlapping. With nothing stored there is nothing to page from, and
  # nothing is asked: the answer is false rather than a request the provider refuses.
  def request_history(contact, count: nil, before: nil)
    raise Whatsapp::Session::Errors::NotSupported, I18n.t('errors.inboxes.channel.history_sync_unsupported') unless capability?('history_sync')

    if backend.class.history_needs_anchor?
      before ||= oldest_stored_message(contact)
      return false if before.nil?
    end

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

  private

  # What a connect asks for, which is the setting except on a backend whose gap only ever
  # arrives inside the history dump: see Backend.history_on_every_connect?.
  def history_on_connect?
    capability?('history_sync') && (backend.class.history_on_every_connect? || history_sync?)
  end

  def oldest_stored_message(contact)
    Message.where(conversation_id: contact.conversations.where(inbox_id: channel.inbox.id).select(:id))
           .where.not(source_id: nil)
           .reorder(created_at: :asc, id: :asc)
           .first
  end
end
