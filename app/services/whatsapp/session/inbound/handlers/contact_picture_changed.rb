# The contact changed their profile photo. The bytes are not in the event, so the stored
# avatar is refetched.
class Whatsapp::Session::Inbound::Handlers::ContactPictureChanged < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:profile_picture)

    contact = Inbound::ContactLookup.contact(inbox: inbox, party: payload.party)
    return :ignored if contact.nil?

    payload.removed ? remove_avatar(contact) : refresh_avatar(contact)
    :handled
  end

  private

  def remove_avatar(contact)
    contact.avatar.purge if contact.avatar.attached?
  end

  # The stored avatar stays until its replacement is attached, and the two sync markers
  # are cleared first. Purging up front loses the picture for good whenever the download
  # does not happen, which is common: `Avatar::AvatarFromUrlJob` skips a contact synced
  # in the last minute or handed a URL it already fetched, and its `ensure` stamps both
  # markers even on the skipped run, so the next attempt with that URL is skipped as a
  # duplicate too. The markers exist to stop the same picture being fetched over and
  # over, not to suppress the event announcing that the picture changed.
  def refresh_avatar(contact)
    attributes = (contact.additional_attributes || {}).except('last_avatar_sync_at', 'avatar_url_hash')
    contact.update_columns(additional_attributes: attributes) # rubocop:disable Rails/SkipsModelValidations
    Whatsapp::Session::UpdateContactAvatarJob.perform_later(contact, inbox, payload.party.to_h, force: true)
  end
end
