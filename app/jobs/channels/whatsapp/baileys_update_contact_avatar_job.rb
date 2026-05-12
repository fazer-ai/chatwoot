class Channels::Whatsapp::BaileysUpdateContactAvatarJob < ApplicationJob
  queue_as :low

  def perform(contact, inbox, phone)
    return if contact.avatar.attached?

    provider = inbox.channel.provider_service
    return if provider.blank?

    response = provider.get_profile_pic("#{phone}@s.whatsapp.net")
    profile_pic_url = response&.dig('data', 'profilePictureUrl')
    Avatar::AvatarFromUrlJob.perform_later(contact, profile_pic_url) if profile_pic_url
  rescue StandardError => e
    Rails.logger.error "Failed to fetch profile picture for contact #{contact.id}: #{e.message}"
  end
end
