# Fetches a contact's WhatsApp profile picture. Enqueued whenever a contact is seen
# without an avatar, so the dashboard fills in over time instead of blocking the
# message that introduced the contact.
class Whatsapp::Session::UpdateContactAvatarJob < ApplicationJob
  queue_as :low

  # `party` is a serialized Model::Party. `force` is the picture-changed event, which
  # knows the stored avatar is out of date and must refetch over it.
  def perform(contact, inbox, party, force: false)
    return if contact.avatar.attached? && !force

    channel = inbox.channel
    return unless channel.session_capabilities.include?('profile_picture')

    # The command declares an Address, and building it with `new` runs no coercion, so
    # handing it a Party would put the wrong shape on the wire and break every backend
    # that reads the address.
    address = Whatsapp::Session::Model::Party.from_h(party).address
    url = channel.provider_service.profile_picture_url(
      Whatsapp::Session::Model::Commands::ContactProfilePicture.new(party: address)
    )
    ::Avatar::AvatarFromUrlJob.perform_later(contact, url) if url.present?
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.warn("[WHATSAPP SESSION] profile picture failed for contact #{contact.id}: #{e.message}")
  end
end
