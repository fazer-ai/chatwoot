# Brings a group contact in line with what WhatsApp says about the group: its name,
# description, settings, invite code and member list.
#
# It runs from two places, which is why the metadata can be passed in: an event that
# already carries the group (group.joined) supplies it directly, while a scheduled or
# manual sync fetches it through the backend.
class Whatsapp::Session::Groups::Syncer
  Model = Whatsapp::Session::Model

  # Group settings, as WhatsApp names them on the wire and as the dashboard reads them
  # from additional_attributes (the keys the Baileys layer already writes).
  SETTINGS = { announce: 'announce', locked: 'restrict',
               join_approval: 'join_approval_mode', member_add_mode: 'member_add_mode' }.freeze

  attr_reader :channel, :group_contact, :soft

  # `soft` skips the member list: it is the expensive half, and an activity ping only
  # means "something happened in this group", not "the roster changed".
  def initialize(channel:, group_contact:, info: nil, soft: false)
    @channel = channel
    @group_contact = group_contact
    @info = info
    @soft = soft
  end

  def perform
    info = @info || fetch_info
    return if info.blank?

    update_contact(info)
    sync_members(info) unless soft
    update_avatar(info)
    group_contact
  end

  private

  def inbox = channel.inbox

  def fetch_info
    address = Model::Address.parse(group_contact.identifier)
    return if address.blank? || !address.group?

    channel.provider_service.group_info(Model::Commands::GroupInfo.new(group: address))
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.error("[WHATSAPP SESSION] group info failed for #{group_contact.identifier}: #{e.message}")
    nil
  end

  def update_contact(info)
    params = {}
    params[:name] = info.subject if info.subject.present? && group_contact.name != info.subject

    attributes = (group_contact.additional_attributes || {}).merge(synced_attributes(info))
    params[:additional_attributes] = attributes if attributes != group_contact.additional_attributes
    group_contact.update!(params) if params.present?
  end

  def synced_attributes(info)
    attributes = {
      'description' => info.description.presence,
      'owner' => info.owner&.identifier || info.owner&.phone,
      'owner_pn' => info.owner&.phone,
      'invite_code' => info.invite_code.presence,
      'group_last_synced_at' => Time.current.to_i,
      'group_left' => false
    }.compact
    SETTINGS.each { |member, key| attributes[key] = info.public_send(member) unless info.public_send(member).nil? }
    attributes
  end

  def sync_members(info)
    return if info.participants.blank?

    member_ids = info.participants.filter_map { |participant| upsert_member(participant) }
    group_contact.group_memberships.active.where.not(contact_id: member_ids).find_each do |membership|
      membership.update!(is_active: false)
    end
  end

  def upsert_member(participant)
    contact = Whatsapp::Session::Inbound::ContactResolver.new(inbox: inbox, party: participant.party)&.perform&.contact
    return if contact.blank?

    member = GroupMember.find_or_initialize_by(group_contact: group_contact, contact: contact)
    member.assign_attributes(role: participant.admin? ? :admin : :member, is_active: true)
    member.save! if member.changed?
    contact.id
  end

  def update_avatar(info)
    return if info.picture_url.blank?
    return if group_contact.avatar.attached?

    ::Avatar::AvatarFromUrlJob.perform_later(group_contact, info.picture_url)
  end
end
