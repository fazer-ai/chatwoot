# The group photo changed. The new bytes are not in the event, so the avatar is
# refetched and the thread records who changed it.
class Whatsapp::Session::Inbound::Handlers::GroupPictureChanged < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:groups)

    inbound::Locks.with_chat_lock(inbox, payload.group.id) do
      resolver = inbound::GroupResolver.new(inbox: inbox, group: payload.group)
      result = resolver.perform
      conversation = resolver.conversation_for(result.group_contact_inbox)

      inbound::GroupActivityWriter.new(conversation: conversation, actor: payload.actor).write('icon_changed')
      refresh_avatar(result.group_contact)
      :handled
    end
  end

  private

  # A removal has nothing to refetch, and the job returns before purging when the group
  # reports no photo, so asking it to refresh would leave the old image attached for
  # good. It is also the half that needs nothing from the provider, which is why the
  # capability is asked about after this branch and not before it: the event is still
  # worth handling on an inbox that cannot fetch, it just cannot fetch.
  #
  # The refetch calls `group_info`, so without `group_management` the job would go out,
  # be refused, log a warning and leave the old picture -- once per photo change, for
  # every group, forever.
  def refresh_avatar(group_contact)
    return group_contact.avatar.purge if payload.removed && group_contact.avatar.attached?
    return if payload.removed || !capability?(:group_management)

    Whatsapp::Session::UpdateGroupAvatarJob.perform_later(group_contact, force: true, channel: channel)
  end
end
