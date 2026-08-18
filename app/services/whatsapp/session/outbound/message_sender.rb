# Sends one Chatwoot message through a session backend.
#
# What the legacy layer did with a 130-second channel lock (keeping a send and the echo
# of the previous one from crossing) is done here by reserving the WhatsApp id before
# the send: the echo is recognized by that id whether or not the response ever came
# back, so nothing has to be serialized.
class Whatsapp::Session::Outbound::MessageSender
  attr_reader :message

  def initialize(message)
    @message = message
  end

  # Returns the provider message id, or nil when there was nothing to send.
  def perform
    outbound::AnnouncementGuard.new(message).ensure!
    return react if reaction?

    content = build_content
    return mark_unsupported if content.nil?

    result = backend.send_message(
      model::Commands::MessageSend.new(
        message_id: reserved_id, to: recipient, content: content, quoted: quoted, mentions: mentions,
        client_ref: reserved_id
      )
    )
    persist(result)
  end

  private

  # Resolved per call, never aliased into a constant: both are implicit namespaces (no
  # model.rb, no outbound.rb), and a constant would hold the module object from before
  # the last reload, whose autoloads are gone.
  def model = Whatsapp::Session::Model
  def outbound = Whatsapp::Session::Outbound

  def channel = message.inbox.channel
  def backend = channel.session_backend
  def conversation = message.conversation
  def reaction? = message.content_attributes['is_reaction'].present?

  def recipient
    model::Address.for_contact(conversation.contact)
  end

  # The same token twice, because a provider takes it one way or the other. A backend
  # that lets us assign the WhatsApp id uses `message_id` and the echo comes back under
  # it; one that assigns its own id ignores `message_id` and returns `client_ref`
  # untouched. Either way the echo carries the value stored as `pending_source_id`,
  # which is the only thing EchoMatcher can recognize a send by.
  def reserved_id
    @reserved_id ||= outbound::SourceIdReservation.reserve(message)
  end

  def build_content
    return attachment_content if message.attachments.present?
    return text_content if message.outgoing_content.present?

    nil
  end

  def text_content
    model::Content::Text.new(body: outgoing_text)
  end

  # Only the first attachment travels with the message: WhatsApp has no multi-media
  # message, and Chatwoot splits the rest into their own messages upstream.
  def attachment_content
    outbound::AttachmentAdapter.new(message.attachments.first, caption: message.outgoing_content).perform
  end

  # The agent typed "@Name"; WhatsApp matches mentions by id, so the rendered text
  # carries the id and the mention list carries the addresses.
  def outgoing_text
    Whatsapp::MentionConverterService.replace_mentions_in_outgoing_text(
      message.content, message.outgoing_content, channel.account
    )
  end

  def mentions
    return [] if message.content.blank?

    jids = Whatsapp::MentionConverterService.extract_mentions_for_whatsapp(message.content, channel.account)[:mentions]
    Array(jids).filter_map { |jid| model::Address.parse(jid) }
  end

  def quoted
    external_id = message.content_attributes['in_reply_to_external_id']
    return if external_id.blank?

    target = conversation.messages.find_by(source_id: external_id)
    return if target.nil?

    model::Commands::Quoted.new(
      id: target.source_id, from_me: target.outgoing?,
      participant: (model::Address.for_contact(target.sender) if recipient.group? && target.incoming?)
    )
  end

  # A reaction is not a message of its own on WhatsApp: it points at one. Chatwoot
  # keeps a single row per (target, sender) and rewrites it, which is why the send
  # reserves a fresh id every time.
  def react
    target = Message.find_by(id: message.content_attributes['in_reply_to'])
    return mark_unsupported if target.nil?

    result = backend.react_message(
      model::Commands::MessageReact.new(
        message_id: reserved_id, to: recipient, target_id: target.source_id, target_from_me: target.outgoing?,
        target_participant: (model::Address.for_contact(target.sender) if recipient.group? && target.incoming?),
        emoji: message.outgoing_content
      )
    )
    persist(result)
  end

  def persist(result)
    return if result.blank? || result.message_id.blank?

    attributes = { source_id: result.message_id }
    attributes[:external_created_at] = result.timestamp / 1000 if result.timestamp.present?
    message.update_under_lock!(**attributes)

    # The agent deleted the message while this send was in flight: the delete endpoint
    # found no source_id to revoke and left it to whoever wrote one.
    ::Messages::DeleteOnChannelJob.perform_later(message.id) if message.deleted?
    result.message_id
  end

  def mark_unsupported
    message.update_under_lock!(is_unsupported: true)
    nil
  end
end
