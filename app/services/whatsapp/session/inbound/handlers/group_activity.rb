# A hint that these groups have been active. It carries no detail, so it only refreshes
# the chat list order and asks for a soft sync, which is throttled by the sync job.
class Whatsapp::Session::Inbound::Handlers::GroupActivity < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:groups)

    groups = Array(payload.groups).reject { |group| ignorable_chat?(group) }
    return :ignored if groups.empty?

    groups.each { |group| refresh(group) }
    :handled
  end

  private

  def refresh(group)
    inbound::Locks.with_chat_lock(inbox, group.id) do
      resolver = inbound::GroupResolver.new(inbox: inbox, group: group)
      result = resolver.perform
      conversation = resolver.conversation_for(result.group_contact_inbox)

      Contacts::SyncGroupJob.perform_later(result.group_contact, soft: true, channel: channel)
      conversation.update_columns(last_activity_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      conversation.dispatch_conversation_updated_event
    end
  end
end
