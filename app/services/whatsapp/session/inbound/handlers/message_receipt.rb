# Delivery receipts for messages this session sent, and read marks the contact made.
class Whatsapp::Session::Inbound::Handlers::MessageReceipt < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    messages = Array(payload.message_ids).flat_map { |id| find_messages(id).to_a }
    return :ignored if messages.empty?

    updated = messages.count { |message| apply(message) }
    updated.positive? ? :handled : :ignored
  end

  private

  def apply(message)
    seen = mark_conversation_seen(message) if read_on_our_side?(message)
    changed = inbound::StatusTransition.apply(message, payload.type, error: payload.error)
    changed || seen.present?
  end

  # A read receipt for an *incoming* message is one of this account's own devices
  # marking the chat read, so somebody here saw it. A read receipt for an outgoing
  # message is the contact reading us, which says nothing about what we have seen:
  # counting it would clear the unread badge for incoming messages nobody here opened.
  def read_on_our_side?(message)
    payload.type == 'read' && message.incoming?
  end

  # The receipt says the chat was read *at that moment*, not now. Unread counts compare
  # a message's creation time against these markers, so stamping `Time.current` marks
  # every incoming message that arrived since as seen too: a read receipt delivered late,
  # or an HTTP event job running out of order, would clear the badge for messages nobody
  # here has opened. The markers only ever move forward.
  def mark_conversation_seen(message)
    conversation = message.conversation
    seen_at = read_at(message)

    # Compared and written under the row lock. Two read receipts for one conversation can
    # be processed at once, and comparing outside the lock lets both pass against the old
    # value, after which the older receipt can land last and walk the marker backwards,
    # making messages that were already seen show up unread again.
    conversation.with_lock do
      next false if conversation.agent_last_seen_at.present? && conversation.agent_last_seen_at >= seen_at

      attributes = { agent_last_seen_at: seen_at }
      attributes[:assignee_last_seen_at] = seen_at if conversation.assignee_id.present?
      conversation.update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations
      true
    end
  end

  # The receipt's own time when the provider reports one, otherwise the message it names:
  # reading a message cannot have happened before that message existed.
  def read_at(message)
    return Time.zone.at(payload.timestamp / 1000) if payload.timestamp.present?

    message.created_at
  end
end
