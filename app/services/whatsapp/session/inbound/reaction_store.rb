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

  # True when anything is still reacting to this target, from anyone. Cheap enough to ask
  # before resolving a sender, which is what keeps a removal aimed at nothing from
  # creating a contact on its way to doing nothing.
  def self.active?(inbox:, target_id:)
    json = "(content_attributes#>>'{}')::jsonb"
    Message.where(inbox_id: inbox.id)
           .where("#{json}->>'is_reaction' = 'true'")
           .where("#{json}->>'in_reply_to_external_id' = ?", target_id)
           .where.not(content: '')
           .where("COALESCE(#{json}->>'deleted', 'false') != 'true'")
           .exists?
  end

  def write(conversation)
    existing = find_existing
    return replace(existing) if existing

    conversation.messages.create!(account_id: inbox.account_id, inbox_id: inbox.id, source_id: reaction.id,
                                  sender: reaction.from_me ? nil : sender,
                                  message_type: reaction.from_me ? :outgoing : :incoming,
                                  content: reaction.emoji, content_attributes: new_content_attributes)
  end

  def new_content_attributes
    {
      is_reaction: true,
      in_reply_to_external_id: reaction.target_id,
      external_created_at: reaction.timestamp && (reaction.timestamp / 1000),
      external_sender_name: ('WhatsApp' if reaction.from_me)
    }.compact
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

    # Merged under the row lock: the hash is read to be written back, so reading it off
    # an instance loaded earlier drops whatever another worker put there in between.
    existing.with_lock do
      existing.update!(content: '', content_attributes: existing.content_attributes.merge('deleted' => true))
    end
    Whatsapp::Session::Inbound::ChatList.refresh(existing.conversation)
    existing
  end

  private

  # WhatsApp gives a changed reaction a new id, so the same sender swapping one emoji
  # for another arrives as a fresh event rather than as an edit. One row per (target,
  # sender) is the invariant the removal path depends on: a second row would show both
  # emojis on the bubble and leave one of them behind when the reaction is taken back.
  def replace(existing)
    existing.with_lock do
      existing.update!(
        source_id: reaction.id,
        content: reaction.emoji,
        content_attributes: existing.content_attributes.merge(
          { 'external_created_at' => reaction.timestamp && (reaction.timestamp / 1000) }.compact
        )
      )
    end
    Whatsapp::Session::Inbound::ChatList.refresh(existing.conversation)
    existing
  end

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
end
