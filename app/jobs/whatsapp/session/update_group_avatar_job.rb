# Refetches a group photo. `force` drops the stored one first, which is what a
# picture-changed event needs: the avatar is attached, but it is the old one.
class Whatsapp::Session::UpdateGroupAvatarJob < ApplicationJob
  queue_as :low

  # `channel` is the inbox the event came from. Falling back to `group_channel` picks
  # the group contact's first contact_inbox, which is an arbitrary choice as soon as the
  # same WhatsApp group is in two inboxes of one account: the picture could then be
  # asked of a provider that is not even connected.
  def perform(group_contact, force: false, channel: nil)
    return unless refetch?(group_contact, force)

    channel ||= group_contact.group_channel
    return if channel.blank?

    info = fetch_info(channel, group_contact)
    return if info&.picture_url.blank?

    group_contact.avatar.purge if group_contact.avatar.attached?
    ::Avatar::AvatarFromUrlJob.perform_later(group_contact, info.picture_url)
  end

  private

  def refetch?(group_contact, force)
    force || !group_contact.avatar.attached?
  end

  def fetch_info(channel, group_contact)
    address = Whatsapp::Session::Model::Address.parse(group_contact.identifier)
    return if address.blank?

    channel.provider_service.group_info(Whatsapp::Session::Model::Commands::GroupInfo.new(group: address))
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.warn("[WHATSAPP SESSION] group photo failed for contact #{group_contact.id}: #{e.message}")
    nil
  end
end
