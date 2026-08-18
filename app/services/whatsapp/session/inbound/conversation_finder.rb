# Picks the conversation an inbound message belongs to, or opens one.
#
# Lifted from Whatsapp::IncomingMessageBaseService so the session layer does not have
# to touch that file (it is one of the three the upstream sync keeps rewriting). The
# rules are the upstream ones: a reaction lands in the thread holding its target, and
# everything else follows the inbox reopen policy.
class Whatsapp::Session::Inbound::ConversationFinder
  attr_reader :inbox, :contact, :contact_inbox, :attribution, :reaction_target_id

  # `attribution` is the first-touch payload ({ 'referral' =>, 'entry_point' => }) the
  # message carried, already compacted by the handler.
  def initialize(inbox:, contact:, contact_inbox:, attribution: {}, reaction_target_id: nil)
    @inbox = inbox
    @contact = contact
    @contact_inbox = contact_inbox
    @attribution = attribution.presence || {}
    @reaction_target_id = reaction_target_id
  end

  def perform
    conversation = conversation_for_reaction || conversation_by_inbox_config
    return backfill_first_touch(conversation) if conversation

    ::Conversation.create!(conversation_params)
  end

  private

  # A reaction annotates a message that already exists, so it must land in that
  # message's thread rather than follow the reopen policy: reacting to a message in a
  # resolved conversation would otherwise open a stray blank one.
  def conversation_for_reaction
    return if reaction_target_id.blank?

    inbox.messages.find_by(source_id: reaction_target_id)&.conversation
  end

  def conversation_by_inbox_config
    # Scoped to the contact across all its contact_inboxes: one person can hold several
    # source_ids in the same inbox (phone and LID), and reopen must see all of them.
    conversations = contact.conversations.where(inbox_id: inbox.id)
    return conversations.last if inbox.lock_to_single_conversation

    conversations.where.not(status: :resolved).last
  end

  def conversation_params
    params = {
      account_id: inbox.account_id, inbox_id: inbox.id,
      contact_id: contact.id, contact_inbox_id: contact_inbox.id
    }
    params[:additional_attributes] = attribution if attribution.present?
    params
  end

  # When the message reuses an existing thread, what conversation_params would have
  # persisted on create never lands. Backfill only the keys still missing, so a genuine
  # first touch is never overwritten by a later one.
  def backfill_first_touch(conversation)
    return conversation if attribution.blank?

    existing = conversation.additional_attributes || {}
    missing = attribution.reject { |key, _| existing.key?(key) }
    conversation.update!(additional_attributes: existing.merge(missing)) if missing.present?
    conversation
  end
end
