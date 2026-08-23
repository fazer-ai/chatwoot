# Picks the conversation an inbound message belongs to, or opens one.
#
# Lifted from Whatsapp::IncomingMessageBaseService so the session layer does not have
# to touch that file (it is one of the three the upstream sync keeps rewriting). The
# rules are the upstream ones: a reaction lands in the thread holding its target, and
# everything else follows the inbox reopen policy.
class Whatsapp::Session::Inbound::ConversationFinder
  attr_reader :inbox, :contact, :contact_inbox, :attribution, :reaction_target_id, :archived, :occurred_at

  # `attribution` is the first-touch payload ({ 'referral' =>, 'entry_point' => }) the
  # message carried, already compacted by the handler.
  #
  # `archived` is the history import saying this message predates the inbox's coverage
  # (see Inbound::Coverage): it never had a chance to be answered here, so it must not
  # open work. `occurred_at` is when it actually happened, used to date a thread that has
  # to be created for it.
  # rubocop:disable Metrics/ParameterLists -- every one of these is an independent fact
  # about the message being filed; an options object would only move the list elsewhere.
  def initialize(inbox:, contact:, contact_inbox:, attribution: {}, reaction_target_id: nil, archived: false, occurred_at: nil)
    @inbox = inbox
    @contact = contact
    @contact_inbox = contact_inbox
    @attribution = attribution.presence || {}
    @reaction_target_id = reaction_target_id
    @archived = archived
    @occurred_at = occurred_at
  end
  # rubocop:enable Metrics/ParameterLists

  def perform
    conversation = conversation_for_reaction || conversation_by_inbox_config
    return backfill_first_touch(mark_as_group(conversation)) if conversation

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
    # An archived import takes whatever thread the contact last had, open or resolved. The
    # reopen policy is the wrong question for it twice over: skipping a resolved thread
    # would open a new one for a message from last year, and doing that per message would
    # end an import of nine hundred messages with nine hundred conversations. Landing in
    # the thread that is already on screen is also what the on-demand button means, since
    # it is pressed to see further back in a conversation that exists.
    return conversations.last if archived || inbox.lock_to_single_conversation

    conversations.where.not(status: :resolved).last
  end

  def conversation_params
    params = {
      account_id: inbox.account_id, inbox_id: inbox.id,
      contact_id: contact.id, contact_inbox_id: contact_inbox.id
    }
    params[:additional_attributes] = attribution if attribution.present?
    params[:group_type] = :group if group?
    # Dated to the message, so a thread reads as the past it is: an inbox sorted by
    # creation does not show a decade of history as having started this afternoon, and a
    # conversation never claims to be younger than the messages inside it.
    params[:created_at] = occurred_at if occurred_at.present?
    # Resolved from the start, never resolved afterwards. The difference is the whole
    # reason the archive is free: `notify_status_change` and `create_activity` are
    # after_update callbacks, so a thread born in this state fires no resolution reporting
    # event and writes no "resolved by" line into itself. Transitioning to the same state
    # would do both, and every imported thread would land in today's figures.
    params[:status] = :resolved if archived
    params
  end

  # Asked of the contact rather than passed in: the group contact is the one thing that
  # already knows, and a caller that forgot the flag would open an ordinary thread for a
  # group. A thread that predates the group being recognised as one is repaired here,
  # which is what GroupConversationHandler also does when it reuses a conversation.
  def group? = contact.group_type_group?

  def mark_as_group(conversation)
    conversation.update!(group_type: :group) if group? && !conversation.group_type_group?
    conversation
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
