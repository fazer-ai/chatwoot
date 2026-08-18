# Turns a canonical Party into the ContactInbox that holds it.
#
# WhatsApp addresses the same person by LID in some chats and by phone number in
# others, and a contact can already exist under either. Every inbound path goes
# through here so that consolidation (merging a phone-keyed contact into its LID) and
# the "is this name a placeholder?" rule are decided in exactly one place.
#
# `overwrite` separates the two callers: the peer of a 1:1 chat is authoritative about
# its own phone and identifier, while a group participant is described partially and
# may only fill in what is still blank.
class Whatsapp::Session::Inbound::ContactResolver
  attr_reader :inbox, :party, :overwrite

  def initialize(inbox:, party:, overwrite: false)
    @inbox = inbox
    @party = party
    @overwrite = overwrite
  end

  def perform
    return if party.blank? || party.source_id.blank?

    consolidate
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: party.source_id, inbox: inbox, contact_attributes: contact_attributes
    ).perform

    update_contact(contact_inbox.contact)
    enqueue_avatar(contact_inbox.contact)
    contact_inbox
  end

  private

  # A contact created from a phone-keyed message keeps its own contact_inbox; when the
  # LID for the same person shows up later, this merges the two before the builder can
  # create a second contact.
  def consolidate
    return if party.phone.blank? && party.lid.blank?

    Whatsapp::ContactInboxConsolidationService.new(
      inbox: inbox, phone: party.phone, lid: party.lid, identifier: party.identifier
    ).perform
  end

  def contact_attributes
    {
      name: party.name.presence || party.phone.presence || party.lid,
      phone_number: party.phone_e164,
      identifier: party.identifier
    }.compact
  end

  def update_contact(contact)
    params = {
      phone_number: (party.phone_e164 if update_phone?(contact)),
      identifier: (party.identifier if update_identifier?(contact)),
      name: (party.name if update_name?(contact))
    }.compact
    contact.update!(params) if params.present?
    contact
  end

  def update_phone?(contact)
    return false if party.phone.blank?

    overwrite ? contact.phone_number != party.phone_e164 : contact.phone_number.blank?
  end

  def update_identifier?(contact)
    return false if party.identifier.blank?

    overwrite ? contact.identifier != party.identifier : contact.identifier.blank?
  end

  def update_name?(contact)
    party.name.present? && placeholder_name?(contact.name)
  end

  # A name equal to the contact's phone (in any normalized "9"-variant), to its LID or
  # to the "<lid>@lid" identifier was auto-generated, not typed by a human, so the push
  # name may replace it. Comparing normalized variants is what rescues a contact whose
  # name was stranded by phone normalization.
  def placeholder_name?(name)
    return true if name.blank?
    return true if name == party.identifier

    digits = name.delete('+')
    return false unless digits.match?(/\A\d+\z/)
    return true if digits.in?([party.phone, party.lid].compact)

    party.phone.present? && Whatsapp::Session::PhoneMatch.same_number?(digits, party.phone)
  end

  def enqueue_avatar(contact)
    return if contact.avatar.attached?
    return unless inbox.channel.session_capabilities.include?('profile_picture')

    Whatsapp::Session::UpdateContactAvatarJob.perform_later(contact, inbox, party.to_h)
  end
end
