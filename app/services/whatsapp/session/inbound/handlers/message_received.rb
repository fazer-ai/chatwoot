# A message arrived on the session: from the contact, or from the connected phone (the
# echo of something an agent typed there, or of what Chatwoot itself sent).
class Whatsapp::Session::Inbound::Handlers::MessageReceived < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless actionable?

    inbound::Locks.with_message_lock(inbox, message.id) do
      next :duplicate if find_message(message.id)

      inbound::Locks.with_chat_lock(inbox, chat_lock_ids) do
        # Re-checked under the chat lock: an agent's send can be slow enough for the
        # echo to arrive before its source_id is stored.
        next :duplicate if find_message(message.id)

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
