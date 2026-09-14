# A message arrived on the session: from the contact, or from the connected phone (the
# echo of something an agent typed there, or of what Chatwoot itself sent).
class Whatsapp::Session::Inbound::Handlers::MessageReceived < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless actionable?

    inbound::Locks.with_message_lock(inbox, message.id) do
      stored = find_message(message.id)
      next duplicate_of(stored) if stored

      inbound::Locks.with_chat_lock(inbox, chat_lock_ids) do
        # Re-checked under the chat lock: an agent's send can be slow enough for the
        # echo to arrive before its source_id is stored.
        stored = find_message(message.id)
        next duplicate_of(stored) if stored

        # The echo of a message Chatwoot sent under a reserved id is already stored, and
        # it is matched before anything is resolved: the echo may address the chat by a
        # LID the peer has no contact under yet, and resolving that first would file the
        # person a second time and then look for the reservation on the wrong contact,
        # storing the echo again in a conversation of its own.
        next :handled if echo_matched?

        message.group? ? handle_group : handle_individual
      end
    end
  end

  private

  def message = payload.message

  # A message that is already stored is normally nothing to do again. Two things are
  # not.
  #
  # The first is the message the stored row is only a placeholder for. A message the
  # backend could not decrypt in time is published under the real message's id, and the
  # message itself arrives later under that same id: read as a duplicate, it leaves the
  # bubble saying it could not be read forever, over a message whose text is in the
  # payload that was just dropped.
  #
  # The second is the work that was queued after the row was saved: an attempt that
  # committed the row and then failed, most often on the job transport, is retried and
  # lands here, and the media it meant to fetch would never be asked for again. The
  # writer decides whether there is anything left to queue.
  def duplicate_of(stored)
    record_first_touch(stored)
    return recovered(stored) if writer_for(stored).reconcile(stored)

    # A row that still owes an announcement, being delivered again: this is the only place that debt
    # can be paid. The content write and the announcement are not one act -- the write commits, and an
    # announcement that fails after it leaves a row nothing marks as owing anything, because
    # committing the content is exactly what stops it being reconcilable. So the row carries the debt
    # itself, and a redelivery of one pays it (#646).
    #
    # Before the bytes, for the same reason the recovery path puts it first: the fetch is what a
    # redelivery queues anyway, and a queue that will not take the bytes must not be what keeps the
    # automations waiting for a delivery that may not come.
    announce_owed_recovery(stored) if recovery_owed?(stored)
    inbound::MessageWriter.fetch_media_for(stored, message)
    :duplicate
  end

  # The row says so itself, and it has to: the instant is written in the same save as the content, so
  # there is no moment where the content is committed and the debt is not on record.
  def recovery_owed?(stored)
    stored.content_attributes.to_h[inbound::MessageWriter::RECOVERY_OWED].present?
  end

  # Announce, then clear, and never the other way round. The clearing is what keeps this from
  # evaluating the rules again on every later delivery: a row whose debt is paid says so, and a rule
  # that never matched the recovered body is not offered the body an edit left behind afterwards.
  #
  # Cleared after the enqueue and not before it, because before is indistinguishable from not having
  # marked anything: a dispatch that fails with the debt already cleared loses the automations exactly
  # the way the defect did. The window that leaves is a process that dies between the two, which costs
  # one more announcement later, and that is the direction worth being wrong in.
  def announce_owed_recovery(stored)
    dispatch_recovery(stored)
    settle_recovery_debt(stored)
  end

  # Off the row the lock reloads, like every other writer of this column: `content_attributes` is one
  # JSON hash, and a merge computed off a stale copy writes away whatever landed in between.
  def settle_recovery_debt(stored)
    stored.update_under_lock!(
      content_attributes: stored.content_attributes.except(inbound::MessageWriter::RECOVERY_OWED)
    )
  end

  # The attribution is the part only the recovery carries: an undecryptable stanza has no
  # readable context, so a thread opened by one starts with no ad and no entry point, and
  # the message that finally arrives is the first and only chance to record them.
  #
  # Asked of every duplicate rather than only of the ones about to be written over, for
  # two reasons. It is about the conversation and not about the row, so nothing that
  # happened to the row disqualifies it -- an edit that reached the placeholder first
  # settles the body and takes the marker off, and the attribution would go down with it.
  # And it costs nothing to ask: it returns on the spot when the message carries no
  # attribution, and otherwise fills only the keys that are still missing.
  #
  # Before the write, and that ordering is the point. Writing the content is what takes
  # the recovery marker off the row, so a failure after it would find the redelivery no
  # longer eligible and lose the attribution for good; failing here leaves the marker
  # where it is and the redelivery does all of it again.
  def record_first_touch(stored)
    inbound::ConversationFinder.backfill_first_touch(stored.conversation, attribution)
  end

  # MESSAGE_UPDATED reaches the open thread and nothing else, so the card in the list
  # would go on showing the bubble that could not be read. It reaches no automation
  # either, and re-firing `message_created` here is not the answer: every rule that does
  # not filter on content already matched the placeholder and already ran. That is #491.
  #
  # After the write rather than before it, unlike the attribution, because losing it
  # costs a stale preview until the next event touches that conversation rather than a
  # fact nothing else records. The media enqueue behind `reconcile` is in the same
  # position and is not lost either way: a redelivery that finds the row already written
  # queues it through `fetch_media_for`, which is the path that exists for exactly this.
  def recovered(stored)
    # The content is readable for the first time, so the automations that were asked about it while the
    # row was a placeholder are asked again (#491). Its own event rather than MESSAGE_CREATED: every
    # other subscriber already ran the arrival, and a second one would double a webhook and an auto-reply.
    #
    # Before the preview refresh, which is the cheaper of the two to lose: a failure between the content
    # write and here leaves the automations unrun for good, because the redelivery finds the row already
    # written and comes back through the duplicate path. That is the behaviour this whole change is
    # about, so it must not be what a refresh of a chat list costs.
    #
    # Announced for a row the history import wrote as well, and the listener is what stands that one
    # down: an imported arrival dispatches nothing at all (Import::SilentWrite), so it left no record of
    # having been evaluated, and a recovery without that record runs no rules. One mechanism rather than
    # a guard here repeating it.
    dispatch_recovery(stored)
    # The debt the write recorded, paid now that the announcement is on the queue. Same order as the
    # redelivery path and for the same reason (#646).
    settle_recovery_debt(stored)
    # Both of these are repaired by a redelivery and the announcement above is not, which is the whole
    # reason it goes first: `fetch_media_for` is what the duplicate path queues anyway, and the next
    # event on the conversation refreshes the list.
    inbound::MessageWriter.fetch_media_for(stored, message)
    inbound::ChatList.refresh(stored.conversation)
    :handled
  end

  def dispatch_recovery(stored)
    Rails.configuration.dispatcher.dispatch(Events::Types::MESSAGE_RECOVERED, Time.zone.now, message: stored)
  end

  # The row already names the conversation and the sender this message belongs to: it was
  # resolved when the placeholder was stored, from the same chat and the same author, and
  # only the content was ever missing.
  def writer_for(stored)
    inbound::MessageWriter.new(conversation: stored.conversation, inbound: message, sender: stored.sender)
  end

  def actionable?
    return false if message.blank? || ignorable_chat?(message.chat)
    return capability?(:groups) if message.group?

    true
  end

  def handle_individual
    contact_inbox = inbound::ContactResolver.new(inbox: inbox, party: peer_party, overwrite: true).perform
    return :ignored if contact_inbox.nil?

    contact = contact_inbox.contact
    return :ignored if silenced?(contact)

    conversation = inbound::ConversationFinder.new(
      inbox: inbox, contact: contact, contact_inbox: contact_inbox, attribution: attribution
    ).perform

    write(conversation, contact)
    dispatch_typing_off(conversation, contact)
    :handled
  end

  def handle_group
    resolver = inbound::GroupResolver.new(inbox: inbox, group: message.chat, sender: message.sender)
    group = resolver.perform

    write(resolver.conversation_for(group.group_contact_inbox), group.sender_contact)
    :handled
  end

  def write(conversation, sender)
    inbound::MessageWriter.new(conversation: conversation, inbound: message, sender: sender).perform
  end

  # Only what the connected phone sent can be the echo of one of our own sends, and
  # skipping the query for everything else keeps it off the path every inbound message
  # takes.
  def echo_matched?
    return false if message.incoming?

    inbound::EchoMatcher.new(inbox: inbox, message_id: message.id, client_ref: message.client_ref).perform.present?
  end

  # Both delegate to Inbound::ChatIdentity, which the history import reads as well: the
  # live path and the import must agree on who a chat belongs to and on the keys that
  # serialize it, or the two file the same person twice.
  def chat_lock_ids = inbound::ChatIdentity.lock_ids(message)
  def peer_party = inbound::ChatIdentity.peer_party(message)

  # The same rule the Cloud path applies (`IncomingMessageBaseService#contact_processable?`):
  # a blocked contact stops generating messages and notifications, but the echo of a
  # reply typed on the connected phone is still stored, or the agent's own answer would
  # go missing from the thread.
  def silenced?(contact)
    contact.blocked? && message.incoming?
  end

  def attribution
    { 'referral' => message.referral, 'entry_point' => message.entry_point }.compact
  end

  # The contact stopped typing by definition once the message landed.
  def dispatch_typing_off(conversation, contact)
    return unless message.incoming?

    Rails.configuration.dispatcher.dispatch(
      Events::Types::CONVERSATION_TYPING_OFF, Time.zone.now,
      conversation: conversation, user: contact, is_private: false
    )
  end
end
