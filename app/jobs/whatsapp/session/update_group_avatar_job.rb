# Refetches a group photo. `force` is what a picture-changed event needs: the avatar is
# attached, but it is the old one.
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

    reset_sync_markers(group_contact) if force
    ::Avatar::AvatarFromUrlJob.perform_later(group_contact, info.picture_url)
  end

  private

  def refetch?(group_contact, force)
    force || !group_contact.avatar.attached?
  end

  # A group contact is a Contact, so `Avatar::AvatarFromUrlJob` applies its rate limit
  # and its URL hash to it, skips a group synced in the last minute, and stamps both
  # markers even on the run it skipped. Without this the forced refresh is dropped and
  # the next attempt with the same URL is dropped as a duplicate. The stored avatar is
  # not purged: the attach replaces it, and purging first loses the picture whenever the
  # download does not happen. Same reset the Baileys path does before its own refetch.
  def reset_sync_markers(group_contact)
    attributes = (group_contact.additional_attributes || {}).except('last_avatar_sync_at', 'avatar_url_hash')
    group_contact.update_columns(additional_attributes: attributes) # rubocop:disable Rails/SkipsModelValidations
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
