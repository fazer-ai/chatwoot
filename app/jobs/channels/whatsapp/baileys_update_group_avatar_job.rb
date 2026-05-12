class Channels::Whatsapp::BaileysUpdateGroupAvatarJob < ApplicationJob
  queue_as :low

  def perform(group_contact, force: false)
    provider = group_contact.group_channel&.provider_service
    return if provider.blank?

    provider.try_update_group_avatar(group_contact, force: force)
  end
end
