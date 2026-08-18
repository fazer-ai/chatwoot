# The group photo changed. The new bytes are not in the event, so the avatar is
# refetched and the thread records who changed it.
class Whatsapp::Session::Inbound::Handlers::GroupPictureChanged < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:groups)

    Inbound::Locks.with_chat_lock(inbox, payload.group.id) do
      resolver = Inbound::GroupResolver.new(inbox: inbox, group: payload.group)
      result = resolver.perform
      conversation = resolver.conversation_for(result.group_contact_inbox)

      Inbound::GroupActivityWriter.new(conversation: conversation, actor: payload.actor).write('icon_changed')
      Whatsapp::Session::UpdateGroupAvatarJob.perform_later(result.group_contact, force: true)
      :handled
    end
  end
end
