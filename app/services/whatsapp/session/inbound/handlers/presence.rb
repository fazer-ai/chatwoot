# Typing and recording indicators, and the online/offline signal that turns them off.
#
# Both are gated by `presence_subscribe`: subscribing to a contact's presence is what
# makes WhatsApp send these at all, and an operator who did not opt in should not have
# the dashboard reacting to them either.
class Whatsapp::Session::Inbound::Handlers::Presence < Whatsapp::Session::Inbound::Handlers::Base
  include Events::Types

  STATES = {
    'composing' => CONVERSATION_TYPING_ON,
    'recording' => CONVERSATION_RECORDING,
    'paused' => CONVERSATION_TYPING_OFF,
    'available' => CONVERSATION_TYPING_OFF,
    'unavailable' => CONVERSATION_TYPING_OFF
  }.freeze

  def perform
    return :ignored unless subscribed?

    event_name = STATES[payload.state]
    return :ignored if event_name.blank?
    return :ignored if chat_presence? && ignorable_chat?(payload.chat)
    # A group types on behalf of one participant; Chatwoot's indicator is per contact.
    return :ignored if chat_presence? && payload.chat.group?

    dispatch(event_name)
  end

  private

  def chat_presence? = payload.is_a?(Model::Events::ChatPresence)

  def subscribed?
    channel.provider_config&.dig('presence_subscribe').present?
  end

  def dispatch(event_name)
    contact_inbox = find_contact_inbox
    return :ignored if contact_inbox.nil?

    conversation = inbox.conversations.where(contact_id: contact_inbox.contact_id).where.not(status: :resolved).last
    return :ignored if conversation.nil?

    Rails.configuration.dispatcher.dispatch(
      event_name, Time.zone.now, conversation: conversation, user: contact_inbox.contact, is_private: false
    )
    :handled
  end

  # The party is addressed by LID in one event and by phone in the next, and only one
  # of them may have a contact_inbox yet.
  def find_contact_inbox
    party = chat_presence? ? (payload.sender || Model::Party.from_address(payload.chat)) : payload.party
    return if party.blank?

    contact_inbox = inbox.contact_inboxes.find_by(source_id: [party.lid, party.phone].compact)
    contact_inbox || find_by_phone(party)
  end

  # Every ninth-digit form, for the same reason the contact and picture resolvers try
  # them: the event carries whichever form WhatsApp uses and the contact is stored under
  # whichever one reached us first. An exact match drops the typing indicator silently.
  def find_by_phone(party)
    numbers = Whatsapp::Session::PhoneMatch.variants(party.phone).map { |variant| "+#{variant}" }
    return if numbers.empty?

    contact = inbox.contacts.find_by(phone_number: numbers)
    inbox.contact_inboxes.find_by(contact_id: contact.id) if contact
  end
end
