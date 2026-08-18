# Reactions are stored as ordinary message rows flagged `is_reaction`, one row per
# (target, sender), toggled instead of duplicated. This holds both halves of that:
# writing a new reaction and marking an existing one removed.
class Whatsapp::Session::Inbound::ReactionStore
  attr_reader :inbox, :reaction, :sender

  # `sender` is the Contact that reacted, nil for a reaction sent from the phone.
  def initialize(inbox:, reaction:, sender: nil)
    @inbox = inbox
    @reaction = reaction
    @sender = sender
  end

  def write(conversation)
    conversation.messages.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: reaction.id,
      sender: reaction.from_me ? nil : sender,
      message_type: reaction.from_me ? :outgoing : :incoming,
      content: reaction.emoji,
      content_attributes: {
        is_reaction: true,
        in_reply_to_external_id: reaction.target_id,
        external_created_at: reaction.timestamp && (reaction.timestamp / 1000),
        external_sender_name: ('WhatsApp' if reaction.from_me)
      }.compact
    )
  end

  # WhatsApp delivers a removal as a reaction with an empty emoji. The stored row is
  # emptied and flagged deleted rather than removed, so the bubble it annotates keeps
  # its history.
  #
  # A `from_me` removal reaches this from two paths and both must work: the echo of a
  # removal Chatwoot itself made (the row is already deleted, so this no-ops) and a
  # removal made on the connected phone (the row is still active, stored sender-less).
  def remove
    existing = find_existing
    return if existing.nil?

    existing.update!(content: '', content_attributes: existing.content_attributes.merge('deleted' => true))
    refresh_chat_list(existing.conversation)
    existing
  end

  private

  # Deliberately not scoped to any conversation: the original reaction may live in an
  # older or resolved thread while the inbound flow picked a different one.
  def find_existing
    json = "(content_attributes#>>'{}')::jsonb"
    base = Message.where(inbox_id: inbox.id)
                  .where("#{json}->>'is_reaction' = 'true'")
                  .where("#{json}->>'in_reply_to_external_id' = ?", reaction.target_id)
    matches = if reaction.from_me
                # Written from the phone: no agent on the row, stored outgoing.
                base.where(sender_id: nil, sender_type: nil).where(message_type: Message.message_types[:outgoing])
              else
                base.where(sender: sender)
              end

    # Active-only: when every match is already deleted this returns nil, so an echoed
    # removal does not re-delete the row and bump the conversation again.
    matches.where.not(content: '')
           .where("COALESCE(#{json}->>'deleted', 'false') != 'true'")
           .reorder(created_at: :desc)
           .first
  end

  # The MESSAGE_UPDATED cable only refreshes the open thread, so without this the chat
  # list preview stays pointed at the reaction that was just removed. Touching
  # updated_at also lets the frontend drop cables that arrive out of order.
  def refresh_chat_list(conversation)
    conversation.update_columns(updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    conversation.dispatch_conversation_updated_event
  end
end
