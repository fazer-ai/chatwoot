# The session was added to a group (or created one). The event carries the whole group,
# so the contact, its settings and its members are written without asking the provider
# anything.
class Whatsapp::Session::Inbound::Handlers::GroupJoined < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:groups)
    return :ignored if payload.info.blank?

    inbound::Locks.with_chat_lock(inbox, payload.info.group.id) { sync }
  end

  private

  def sync
    resolver = inbound::GroupResolver.new(inbox: inbox, group: payload.info.group, subject: payload.info.subject)
    result = resolver.perform
    # Opened right away so the group shows up in the chat list with its history, the
    # same as a group whose first message just arrived.
    resolver.conversation_for(result.group_contact_inbox)

    Whatsapp::Session::Groups::Syncer.new(channel: channel, group_contact: result.group_contact, info: payload.info).perform
    broadcast_roster(result.group_contact)
    :handled
  end

  # The roster changed, and an ordinary contact update does not carry `group_members`,
  # so without this an open dashboard keeps showing the members (and the admin rights)
  # the group had before, until a reload or the next participant event.
  def broadcast_roster(group_contact)
    group_contact.reload
    Rails.configuration.dispatcher.dispatch(Events::Types::CONTACT_GROUP_SYNCED, Time.zone.now, contact: group_contact)
  end
end
