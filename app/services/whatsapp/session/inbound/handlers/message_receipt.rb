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
    changed = Inbound::StatusTransition.apply(message, payload.type, error: payload.error)
    changed || seen.present?
  end

  # A read receipt for an *incoming* message is one of this account's own devices
  # marking the chat read, so somebody here saw it. A read receipt for an outgoing
  # message is the contact reading us, which says nothing about what we have seen:
  # counting it would clear the unread badge for incoming messages nobody here opened.
  def read_on_our_side?(message)
    payload.type == 'read' && message.incoming?
  end

  # Independent of whether the status moved: a chat marked read twice is still read, and
  # the seen timestamps have to follow the second mark as well.
  def mark_conversation_seen(message)
    conversation = message.conversation
    attributes = { agent_last_seen_at: Time.current }
    attributes[:assignee_last_seen_at] = Time.current if conversation.assignee_id.present?
    conversation.update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations
    true
  end
end
