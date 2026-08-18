# The session was added to a group (or created one). The event carries the whole group,
# so the contact, its settings and its members are written without asking the provider
# anything.
class Whatsapp::Session::Inbound::Handlers::GroupJoined < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:groups)
    return :ignored if payload.info.blank?

    Inbound::Locks.with_chat_lock(inbox, payload.info.group.id) { sync }
  end

  private

  def sync
    resolver = Inbound::GroupResolver.new(inbox: inbox, group: payload.info.group, subject: payload.info.subject)
    result = resolver.perform
    # Opened right away so the group shows up in the chat list with its history, the
    # same as a group whose first message just arrived.
    resolver.conversation_for(result.group_contact_inbox)

    Whatsapp::Session::Groups::Syncer.new(channel: channel, group_contact: result.group_contact, info: payload.info).perform
    :handled
  end
end
