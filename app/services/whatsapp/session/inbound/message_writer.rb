# Turns a canonical InboundMessage into the Chatwoot message row (or rows, for shared
# contacts). Every provider in the session family goes through this one writer, so the
# stored shape does not depend on who delivered the message.
#
# Media is not downloaded here: the bytes are fetched by MediaFetchJob and attached
# afterwards. Downloading inline would stall the consumer thread that keeps a session's
# events in order, and the attachment lands within seconds either way.
class Whatsapp::Session::Inbound::MessageWriter
  Content = Whatsapp::Session::Model::Content

  attr_reader :conversation, :inbound, :sender

  def initialize(conversation:, inbound:, sender: nil)
    @conversation = conversation
    @inbound = inbound
    @sender = sender
  end

  def perform
    return build_contact_messages if content.is_a?(Content::Contacts)

    message = conversation.messages.build(content: message_content, **message_attributes)
    attach_location(message)
    message.save!
    enqueue_media_fetch(message)
    message
  end

  private

  def inbox = conversation.inbox
  def content = inbound.content
  def incoming? = inbound.incoming?

  def message_attributes
    {
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: inbound.id,
      sender: incoming? ? sender : nil,
      message_type: incoming? ? :incoming : :outgoing,
      content_attributes: content_attributes
    }
  end

  def message_content
    case content
    when Content::Text then convert_mentions(content.body)
    when Content::Media then content.caption
    when Content::Rich then content.preview_text
    end
  end

  def content_attributes
    {
      external_created_at: inbound.timestamp && (inbound.timestamp / 1000),
      # An outgoing message stored without a sender was written on the phone, not by an
      # agent; the dashboard needs a name to show in the bubble, and `human_response?`
      # needs the flag to count the reply as one, so it clears `waiting_since` and
      # registers a first response like an agent's own message would. Anything Chatwoot
      # itself sent was matched by its reserved id and never reaches this writer.
      external_echo: (true unless incoming?),
      external_sender_name: ('WhatsApp' unless incoming?),
      in_reply_to_external_id: inbound.quoted_id.presence,
      referral: inbound.referral.presence,
      is_unsupported: (true if unsupported?),
      rich: (content.to_content_attribute if content.is_a?(Content::Rich))
    }.compact
  end

  # A rich card with no text and no media header renders as an empty bubble, which is
  # what the unsupported flag exists for.
  def unsupported?
    return true if content.is_a?(Content::Unsupported)

    content.is_a?(Content::Rich) && content.preview_text.blank? && content.media.blank?
  end

  def convert_mentions(text)
    return text if text.blank? || inbound.mentions.blank?

    Whatsapp::MentionConverterService.convert_incoming_mentions(
      text, { mentionedJid: Array(inbound.mentions).map(&:to_jid) }, inbox.account, inbox
    )
  end

  # Location carries no downloadable bytes: the coordinates are the attachment.
  def attach_location(message)
    return unless content.is_a?(Content::Location)

    name = [content.name, content.address].compact_blank.join(', ')
    message.attachments.build(
      account_id: inbox.account_id,
      file_type: :location,
      coordinates_lat: content.latitude,
      coordinates_long: content.longitude,
      fallback_title: name.presence
    )
  end

  # A rich card carries its header image, video or document in `media`, which is the
  # same downloadable reference a plain media message has: without this the card is
  # stored with its text and no attachment.
  def enqueue_media_fetch(message)
    media = content if content.is_a?(Content::Media)
    media ||= content.media if content.is_a?(Content::Rich)
    return if media.blank? || media.ref.blank?

    Whatsapp::Session::MediaFetchJob.perform_later(message, media.to_h)
  end

  # One message per shared contact, each with a native contact attachment, so the
  # dashboard renders them in the contact bubble instead of as plain text.
  def build_contact_messages
    messages = Array(content.contacts).filter_map { |card| build_contact_message(card) }
    messages.last
  end

  def build_contact_message(card)
    card = card.stringify_keys
    phone = card['phone'].presence
    # `display_name` is what the contract calls it. Reading `name` found nothing, so a
    # card with a phone lost its name and a name-only card was dropped entirely, leaving
    # the conversation that had just been opened with no message in it.
    name = card['display_name'].presence
    return if phone.blank? && name.blank?

    message = conversation.messages.build(content: contact_line(name, phone), **message_attributes)
    message.attachments.build(
      account_id: inbox.account_id, file_type: :contact,
      fallback_title: phone || name, meta: { firstName: name }.compact
    )
    message.save!
    message
  end

  def contact_line(name, phone)
    return name if phone.blank?
    return phone if name.blank? || name.start_with?('+')

    "#{name} - #{phone}"
  end
end
