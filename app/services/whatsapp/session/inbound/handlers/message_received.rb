# A message arrived on the session: from the contact, or from the connected phone (the
# echo of something an agent typed there, or of what Chatwoot itself sent).
class Whatsapp::Session::Inbound::Handlers::MessageReceived < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless actionable?

    Inbound::Locks.with_message_lock(inbox, message.id) do
      next :duplicate if find_message(message.id)

      Inbound::Locks.with_chat_lock(inbox, message.chat.id) do
        # Re-checked under the chat lock: an agent's send can be slow enough for the
        # echo to arrive before its source_id is stored.
        next :duplicate if find_message(message.id)

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
    contact_inbox = Inbound::ContactResolver.new(inbox: inbox, party: peer_party, overwrite: true).perform
    return :ignored if contact_inbox.nil?

    contact = contact_inbox.contact
    # The echo of a message Chatwoot sent under a reserved id is already stored;
    # matching it before a conversation is picked keeps it from reopening (or opening)
    # a thread just to hold a message that is already there.
    return :handled if Inbound::EchoMatcher.new(inbox: inbox, contact: contact, message_id: message.id).perform

    conversation = Inbound::ConversationFinder.new(
      inbox: inbox, contact: contact, contact_inbox: contact_inbox, attribution: attribution
    ).perform

    write(conversation, contact)
    dispatch_typing_off(conversation, contact)
    :handled
  end

  def handle_group
    resolver = Inbound::GroupResolver.new(inbox: inbox, group: message.chat, sender: message.sender)
    group = resolver.perform
    return :handled if Inbound::EchoMatcher.new(inbox: inbox, contact: group.group_contact, message_id: message.id).perform

    write(resolver.conversation_for(group.group_contact_inbox), group.sender_contact)
    :handled
  end

  def write(conversation, sender)
    Inbound::MessageWriter.new(conversation: conversation, inbound: message, sender: sender).perform
  end

  # In a 1:1 chat the other side is the chat itself; `sender` is the author, which is
  # the session owner on an echo and therefore not who the conversation belongs to.
  # An incoming message carries the richer Party (phone and LID together), so it wins.
  def peer_party
    return message.sender if message.incoming? && message.sender.present?

    Model::Party.from_address(message.chat)
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
