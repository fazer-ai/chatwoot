# The contact changed their profile photo. The bytes are not in the event, so the
# stored avatar is dropped and refetched.
class Whatsapp::Session::Inbound::Handlers::ContactPictureChanged < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:profile_picture)

    contact = find_contact
    return :ignored if contact.nil?

    contact.avatar.purge if contact.avatar.attached?
    return :handled if payload.removed

    Whatsapp::Session::UpdateContactAvatarJob.perform_later(contact, inbox, payload.party.to_h)
    :handled
  end

  private

  def find_contact
    return if payload.party.blank?

    inbox.contact_inboxes.find_by(source_id: [payload.party.lid, payload.party.phone].compact)&.contact
  end
end
