# Something changed in a group: its name, its description, one of its settings, or who
# is in it. Each change becomes an activity message in the group thread and, where the
# dashboard reads it, an attribute on the group contact.
class Whatsapp::Session::Inbound::Handlers::GroupUpdated < Whatsapp::Session::Inbound::Handlers::Base
  SETTINGS = Whatsapp::Session::Groups::Syncer::SETTINGS

  def perform
    return :ignored unless capability?(:groups)
    return :ignored if changes.blank?

    Inbound::Locks.with_chat_lock(inbox, payload.group.id) do
      apply
      :handled
    end
  end

  private

  def changes = payload.changes

  def apply
    @resolver = Inbound::GroupResolver.new(inbox: inbox, group: payload.group)
    result = @resolver.perform
    @group_contact = result.group_contact
    @conversation = @resolver.conversation_for(result.group_contact_inbox)
    @activity = Inbound::GroupActivityWriter.new(conversation: @conversation, actor: payload.actor)

    apply_subject
    apply_description
    apply_settings
    apply_participants
    dispatch_group_synced
  end

  def apply_subject
    return if changes.subject.blank?

    @group_contact.update!(name: changes.subject)
    @activity.write('subject_changed', value: changes.subject)
  end

  # An empty (not absent) description is the group removing it.
  def apply_description
    return if changes.description.nil?

    merge_attributes('description' => changes.description.presence)
    @activity.write(changes.description.present? ? 'description_changed' : 'description_removed')
  end

  def apply_settings
    SETTINGS.each do |member, key|
      raw = changes.public_send(member)
      next if raw.nil?

      value = Whatsapp::Session::Groups::Syncer.setting_value(member, raw)
      merge_attributes(key => value)
      @activity.write("#{key}_#{value ? 'enabled' : 'disabled'}")
    end
  end

  def apply_participants
    %w[join leave promote demote].each do |action|
      parties = Array(changes.public_send(action))
      next if parties.blank?

      contacts = parties.filter_map { |party| resolve_participant(party) }
      next if contacts.empty?

      contacts.each { |contact| apply_membership(action, contact) }
      @activity.write_participants(activity_action(action, parties), contacts)
      resolve_conversations_if_left(action, contacts)
    end
  end

  def resolve_participant(party)
    Inbound::ContactResolver.new(inbox: inbox, party: party)&.perform&.contact
  end

  def apply_membership(action, contact)
    case action
    when 'join' then @resolver.add_member(@group_contact, contact)
    when 'leave' then @resolver.remove_member(@group_contact, contact)
    when 'promote' then @resolver.update_member_role(@group_contact, contact, :admin)
    when 'demote' then @resolver.update_member_role(@group_contact, contact, :member)
    end
  end

  # WhatsApp reports "someone was added" and "someone joined by link" the same way; the
  # difference is whether an actor did it.
  def activity_action(action, parties)
    case action
    when 'join' then payload.actor.blank? ? 'join' : 'add'
    when 'leave' then leaving_by_self?(parties) ? 'leave' : 'remove'
    else action
    end
  end

  def leaving_by_self?(parties)
    return true if payload.actor.blank?

    parties.any? { |party| party.source_id == payload.actor.source_id }
  end

  # The session's own number left the group: nothing more will arrive in that thread.
  def resolve_conversations_if_left(action, contacts)
    return unless action == 'leave'
    return unless contacts.any? { |contact| Whatsapp::Session::PhoneMatch.same_number?(contact.phone_number, channel.phone_number) }

    merge_attributes('group_left' => true)
    @group_contact.contact_inboxes.each do |contact_inbox|
      contact_inbox.conversations.where(status: %i[open pending]).find_each { |thread| thread.update!(status: :resolved) }
    end
  end

  def merge_attributes(attributes)
    merged = (@group_contact.additional_attributes || {}).merge(attributes)
    @group_contact.update!(additional_attributes: merged) if merged != @group_contact.additional_attributes
  end

  def dispatch_group_synced
    @group_contact.reload
    Rails.configuration.dispatcher.dispatch(Events::Types::CONTACT_GROUP_SYNCED, Time.zone.now, contact: @group_contact)
  end
end
