# Delivery receipts for messages this session sent, and read marks the contact made.
class Whatsapp::Session::Inbound::Handlers::MessageReceipt < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    messages = Array(payload.message_ids).filter_map { |id| find_message(id) }
    return :ignored if messages.empty?

    updated = messages.count { |message| apply(message) }
    updated.positive? ? :handled : :ignored
  end

  private

  def apply(message)
    changed = Inbound::StatusTransition.apply(message, payload.type, error: payload.error)
    mark_conversation_seen(message) if changed && payload.type == 'read'
    changed
  end

  # The contact read what the agent sent, so the unread badge on the agent's side has
  # nothing left to report.
  def mark_conversation_seen(message)
    conversation = message.conversation
    attributes = { agent_last_seen_at: Time.current }
    attributes[:assignee_last_seen_at] = Time.current if conversation.assignee_id.present?
    conversation.update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations
  end
end
