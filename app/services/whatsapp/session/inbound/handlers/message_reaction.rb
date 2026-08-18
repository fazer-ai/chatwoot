# Someone reacted to a message, or took their reaction back.
class Whatsapp::Session::Inbound::Handlers::MessageReaction < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless actionable?

    Inbound::Locks.with_chat_lock(inbox, payload.chat.id) do
      payload.removal? ? remove : add
    end
  end

  private

  def actionable?
    return false if ignorable_chat?(payload.chat)
    return capability?(:groups) if payload.chat.group?

    true
  end

  def remove
    store(sender_contact).remove ? :handled : :ignored
  end

  def add
    return :duplicate if find_message(payload.id)

    contact_inbox = resolve_contact_inbox
    return :ignored if contact_inbox.nil?

    conversation = conversation_for(contact_inbox)
    return :ignored if conversation.nil?

    store(payload.chat.group? ? sender_contact : contact_inbox.contact).write(conversation)
    :handled
  end

  def store(sender)
    Inbound::ReactionStore.new(inbox: inbox, reaction: payload, sender: sender)
  end

  # The reaction belongs in the thread holding the message it annotates. Without a
  # stored target there is nothing to annotate, so the reaction is dropped rather than
  # opening a thread of its own.
  def conversation_for(contact_inbox)
    target = find_message(payload.target_id)
    return target.conversation if target

    return nil if payload.chat.group?

    Inbound::ConversationFinder.new(inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox).perform
  end

  def resolve_contact_inbox
    return group_result&.group_contact_inbox if payload.chat.group?

    Inbound::ContactResolver.new(inbox: inbox, party: peer_party, overwrite: true).perform
  end

  def sender_contact
    return nil if payload.from_me

    payload.chat.group? ? group_result&.sender_contact : resolve_contact_inbox&.contact
  end

  def group_result
    @group_result ||= Inbound::GroupResolver.new(inbox: inbox, group: payload.chat, sender: payload.sender).perform
  end

  def peer_party
    return payload.sender if !payload.from_me && payload.sender.present?

    Model::Party.from_address(payload.chat)
  end
end
