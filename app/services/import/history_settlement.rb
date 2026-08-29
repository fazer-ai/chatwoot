# What an import owes a conversation after the rows are in.
#
# Writing history with the ordinary callbacks suppressed (see SilentWrite) leaves the two
# clocks the inbox sorts and reports by untouched, and a thread the run opened carrying
# stamps that describe the import rather than the conversation. Both are put right here,
# once per conversation instead of once per message, and only in the direction that is
# true.
#
# Shared because there are several importers and only one correct answer: the session
# layer files the canonical WhatsApp providers, the Baileys one runs the legacy pipeline
# for the frozen provider, and the IMAP one files a mailbox. None of this is channel
# specific -- it is Conversation and Message bookkeeping -- so a copy in each would drift,
# and the drift would show up as a thread sorted to the wrong place in the list, which
# nobody reads as a bug in an importer.
#
# The includer provides two things: `opened`, the ids of conversations this run created,
# and `announcing`, the block wrapper that lets the dashboard push through.
module Import::HistorySettlement
  private

  # Both halves are settled together rather than one after the other, because a chat can
  # hand rows to each and the stamps have to see all of them at once: split in two, the
  # archive pass would read a conversation's rows without the newer gap rows beside them.
  # Which conversations may announce is therefore carried separately from the rows.
  def settle(archived, gap)
    announced = gap.compact.filter_map(&:conversation).uniq
    (archived + gap).compact.group_by(&:conversation).each do |conversation, rows|
      stamp_activity(conversation, rows)
      stamp_waiting(conversation, rows)
      stamp_seen(conversation, rows)
      stamp_contact(conversation, rows)
      if announced.include?(conversation)
        announcing { Whatsapp::Session::Inbound::ChatList.refresh(conversation) }
      else
        Whatsapp::Session::Inbound::ChatList.refresh(conversation)
      end
    end
  end

  # Where the inbox sorts, and where a thread appears in the list. `set_conversation_activity`
  # assigns whatever row it has just written, unconditionally: left to run over history it
  # would drag a thread answered this morning back to 2025. A thread this run opened takes
  # the batch outright, because it was born stamped with the time of the import; one that
  # already existed only ever moves forward.
  def stamp_activity(conversation, rows)
    newest = rows.filter_map(&:created_at).max
    return if newest.blank?
    return if opened.exclude?(conversation.id) && conversation.last_activity_at.present? &&
              conversation.last_activity_at >= newest

    conversation.update_columns(last_activity_at: newest) # rubocop:disable Rails/SkipsModelValidations
  end

  # The clock the queue and the unattended reports read. Live traffic keeps it by hand: a
  # message from the contact starts it, an answer of ours clears it. An archive thread is
  # resolved and runs no clock at all; an open one gets the same reading live traffic
  # would have left, taken over the whole batch.
  #
  # The archive has to be cleared rather than skipped. `handle_resolved_status_change`
  # clears the clock on a thread that *becomes* resolved, and an archive thread is born
  # resolved instead, so that callback never sees a status change -- leaving whatever
  # `ensure_waiting_since` stamped on it at creation. `Conversation.unattended` reads
  # `waiting_since` with no status of its own, so an import would otherwise file every
  # thread it created as unattended forever.
  def stamp_waiting(conversation, rows)
    return clear_waiting(conversation) if conversation.resolved?

    waiting_since = first_unanswered(rows)
    return unless restamp_waiting?(conversation, waiting_since)

    conversation.update_columns(waiting_since: waiting_since) # rubocop:disable Rails/SkipsModelValidations
  end

  def clear_waiting(conversation)
    return if conversation.waiting_since.blank?

    conversation.update_columns(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations
  end

  # The unread badge the conversation list draws. `unread_messages` counts every message
  # when `agent_last_seen_at` is nil, so an archive filed resolved -- filed that way
  # precisely so it asks for no attention -- would still arrive wearing a count.
  #
  # A thread holding nothing but imported incoming rows is the test, rather than one this
  # run created: a dump arrives in frames filed by separate workers, so the thread a later
  # frame adds to was created by a worker whose `opened` this one cannot see, and keying on
  # that left a stamp three minutes behind the newest row. What the test protects is the
  # same thing either way -- on a thread that ever received live traffic an unread message
  # is somebody's real backlog, and hiding it would be the worse error.
  #
  # Read off the thread rather than off `rows`, and never moved backwards, so frames may
  # land in any order and each one leaves the same answer.
  # When the contact last said anything, which the dashboard sorts and filters contacts by.
  # Live traffic keeps it in `Message#update_contact_activity`, inside the after-create
  # callbacks the import suppresses wholesale -- so without this an imported contact has a
  # decade of mail and a null clock, and sorts below people who have never written.
  #
  # Not the value the live path would have written, which is `DateTime.now`: on a replay
  # that stamps every contact in the archive with the moment of the import. The row's own
  # date is the true answer, taken only from incoming rows because it is the contact's
  # activity and not ours, and only ever forwards -- a contact with live traffic has a real
  # clock and history must not drag it backwards.
  def stamp_contact(conversation, rows)
    newest = rows.select(&:incoming?).filter_map(&:created_at).max
    return if newest.blank?

    contact = conversation.contact
    return if contact.blank? || (contact.last_activity_at.present? && contact.last_activity_at >= newest)

    contact.update_columns(last_activity_at: newest) # rubocop:disable Rails/SkipsModelValidations
  end

  def stamp_seen(conversation, _rows)
    return unless conversation.resolved?
    return if conversation.messages.incoming.where.not(Import::IMPORTED_SQL).exists?

    newest = conversation.messages.maximum(:created_at)
    return if newest.blank?
    return if conversation.agent_last_seen_at.present? && conversation.agent_last_seen_at >= newest

    conversation.update_columns(agent_last_seen_at: newest) # rubocop:disable Rails/SkipsModelValidations
  end

  # A thread this run opened carries what `ensure_waiting_since` stamps on every new
  # conversation, which reads "waiting since now" about a message from Saturday: an
  # artifact, replaced by whatever the batch says, nil included. On a thread that already
  # existed the stored clock is real, and only an older unanswered message may pull it back.
  def restamp_waiting?(conversation, waiting_since)
    return true if opened.include?(conversation.id)
    return false if waiting_since.blank?

    conversation.waiting_since.blank? || conversation.waiting_since > waiting_since
  end

  # The oldest message the contact sent that nothing of ours came after.
  def first_unanswered(rows)
    answered_at = rows.select(&:outgoing?).filter_map(&:created_at).max
    pending = rows.select { |row| row.incoming? && (answered_at.blank? || row.created_at > answered_at) }
    pending.first&.created_at
  end
end
