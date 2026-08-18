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

    by_source_id || by_phone
  end

  def by_source_id
    source_ids = [payload.party.lid, payload.party.phone].compact_blank
    return if source_ids.empty?

    inbox.contact_inboxes.find_by(source_id: source_ids)&.contact
  end

  # A contact inbox keyed by LID is invisible to a lookup holding only the phone, which
  # is what this event carries for a contact that was created before the inbox moved
  # provider. Matched on the contact itself and never created: a photo changing is no
  # reason to invent somebody.
  def by_phone
    phone = payload.party.phone_e164
    return if phone.blank?

    inbox.contact_inboxes.joins(:contact).find_by(contact: { phone_number: phone })&.contact
  end
end
