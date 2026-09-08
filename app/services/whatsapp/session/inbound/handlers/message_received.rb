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

    inbound::MessageWriter.fetch_media_for(stored, message)
    :duplicate
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
    inbound::ChatList.refresh(stored.conversation)
    :handled
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

  # Every id this chat can be addressed by. WhatsApp names the same 1:1 peer by phone in
  # one event and by LID in the next, and both resolve to one contact: locking only the
  # id this event carries lets a worker holding the other alias run alongside, and each
  # opens a conversation of its own.
  def chat_lock_ids
    return [message.chat.id] if message.group?

    # Every ninth-digit form as well: WhatsApp reports a Brazilian or Argentinian line
    # with or without the extra digit, `ContactResolver` files both under one contact,
    # and two keys differing by that digit would not serialize against each other.
    [message.chat.id, peer_party&.lid, *Whatsapp::Session::PhoneMatch.variants(peer_party&.phone)]
  end

  # In a 1:1 chat the other side is the chat itself; `sender` is the author, which is
  # the session owner on an echo and therefore not who the conversation belongs to.
  # An incoming message carries the richer Party (phone and LID together), so it wins.
  def peer_party
    return message.sender if message.incoming? && message.sender.present?

    model::Party.from_address(message.chat)
  end

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
