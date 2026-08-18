# Someone reacted to a message, or took their reaction back.
class Whatsapp::Session::Inbound::Handlers::MessageReaction < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless actionable?

    inbound::Locks.with_chat_lock(inbox, payload.chat.id) do
      payload.removal? ? remove : add
    end
  end

  private

  def actionable?
    return false if ignorable_chat?(payload.chat)
    return capability?(:groups) if payload.chat.group?

    true
  end

  # Checked before the sender is resolved: resolving creates a Contact, a ContactInbox
  # and an avatar job, and a removal aimed at a message nobody here reacted to has
  # nothing to remove. Without this, every stray removal leaves a contact behind.
  def remove
    return :ignored unless inbound::ReactionStore.active?(inbox: inbox, target_id: payload.target_id)

    store(sender_contact).remove ? :handled : :ignored
  end

  def add
    return :duplicate if find_message(payload.id)

    # A reaction Chatwoot sent reserves its id like any other message, so a lost send
    # response makes the echo arrive under an id we never stored. The reservation is
    # what identifies it, on its own and before any contact is resolved; writing again
    # would leave two reactions on the same bubble.
    return :handled if inbound::EchoMatcher.new(inbox: inbox, message_id: payload.id).perform

    # The reaction belongs in the thread holding the message it annotates, and that is
    # checked before anybody is resolved: resolving creates a Contact, a ContactInbox and
    # an avatar job, and a reaction whose target was never stored has nothing to annotate.
    # It is dropped rather than opening a thread of its own to hold it.
    target = find_message(payload.target_id)
    return :ignored if target.nil?

    contact_inbox = resolve_contact_inbox
    return :ignored if contact_inbox.nil?

    store(payload.chat.group? ? sender_contact : contact_inbox.contact).write(target.conversation)
    :handled
  end

  def store(sender)
    inbound::ReactionStore.new(inbox: inbox, reaction: payload, sender: sender)
  end

  def resolve_contact_inbox
    return group_result&.group_contact_inbox if payload.chat.group?

    inbound::ContactResolver.new(inbox: inbox, party: peer_party, overwrite: true).perform
  end

  def sender_contact
    return nil if payload.from_me

    payload.chat.group? ? group_result&.sender_contact : resolve_contact_inbox&.contact
  end

  def group_result
    @group_result ||= inbound::GroupResolver.new(inbox: inbox, group: payload.chat, sender: payload.sender).perform
  end

  def peer_party
    return payload.sender if !payload.from_me && payload.sender.present?

    model::Party.from_address(payload.chat)
  end
end
