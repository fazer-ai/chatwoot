# Refetches a group photo. `force` drops the stored one first, which is what a
# picture-changed event needs: the avatar is attached, but it is the old one.
class Whatsapp::Session::UpdateGroupAvatarJob < ApplicationJob
  queue_as :low

  def perform(group_contact, force: false)
    channel = group_contact.group_channel
    return if channel.blank?
    return if group_contact.avatar.attached? && !force

    info = fetch_info(channel, group_contact)
    return if info&.picture_url.blank?

    group_contact.avatar.purge if group_contact.avatar.attached?
    ::Avatar::AvatarFromUrlJob.perform_later(group_contact, info.picture_url)
  end

  private

  def fetch_info(channel, group_contact)
    address = Whatsapp::Session::Model::Address.parse(group_contact.identifier)
    return if address.blank?

    channel.provider_service.group_info(Whatsapp::Session::Model::Commands::GroupInfo.new(group: address))
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.warn("[WHATSAPP SESSION] group photo failed for contact #{group_contact.id}: #{e.message}")
    nil
  end
end
