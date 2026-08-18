# Finds the contact_inbox a Party already has, and never creates one.
#
# Three keys can hold the same person and only one of them may exist: the source_id the
# event names, the other ninth-digit form of that number, and the phone stored on the
# contact itself, which is all that is left to match on once consolidation re-keyed the
# row to a LID. Presence, picture changes and group activity all ask this same question
# about a party they must not invent, so it is answered here instead of three times.
module Whatsapp::Session::Inbound::ContactLookup
  module_function

  def find(inbox:, party:)
    return if party.blank?

    by_source_id(inbox, party) || by_variant_source_id(inbox, party) || by_contact_phone(inbox, party)
  end

  def contact(inbox:, party:)
    find(inbox: inbox, party: party)&.contact
  end

  def by_source_id(inbox, party)
    keys = [party.lid, party.phone].compact_blank
    return if keys.empty?

    inbox.contact_inboxes.find_by(source_id: keys)
  end

  def by_variant_source_id(inbox, party)
    variants = Whatsapp::Session::PhoneMatch.variants(party.phone) - [party.phone.to_s]
    return if variants.empty?

    inbox.contact_inboxes.find_by(source_id: variants)
  end

  def by_contact_phone(inbox, party)
    numbers = Whatsapp::Session::PhoneMatch.variants(party.phone).map { |variant| "+#{variant}" }
    return if numbers.empty?

    inbox.contact_inboxes.joins(:contact).find_by(contact: { phone_number: numbers })
  end
end
