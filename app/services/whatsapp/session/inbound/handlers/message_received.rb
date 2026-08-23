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

  # A message that is already stored is normally nothing to do again. The exception is
  # the work that was queued after it was saved: an attempt that committed the row and
  # then failed, most often on the job transport, is retried and lands here, and the
  # media it meant to fetch would never be asked for again. The writer decides whether
  # there is anything left to queue.
  def duplicate_of(stored)
    inbound::MessageWriter.fetch_media_for(stored, message)
    :duplicate
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
