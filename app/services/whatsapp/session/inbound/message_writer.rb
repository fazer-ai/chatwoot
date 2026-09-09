# Turns a canonical InboundMessage into the Chatwoot message row (or rows, for shared
# contacts). Every provider in the session family goes through this one writer, so the
# stored shape does not depend on who delivered the message.
#
# Media is not downloaded here: the bytes are fetched by MediaFetchJob and attached
# afterwards. Downloading inline would stall the consumer thread that keeps a session's
# events in order, and the attachment lands within seconds either way.
class Whatsapp::Session::Inbound::MessageWriter
  attr_reader :conversation, :inbound, :sender

  def initialize(conversation:, inbound:, sender: nil)
    @conversation = conversation
    @inbound = inbound
    @sender = sender
  end

  # The media an inbound message carries, whichever shape holds it, or nil.
  def self.media_in(inbound)
    content = inbound.content
    media = content if content&.wire_type == 'media'
    media ||= content.media if content&.wire_type == 'rich'
    media if media.present? && media.ref.present?
  end

  # Queues the fetch for a message that is already stored.
  #
  # The row is committed before the job is queued, so an attempt that failed in between
  # (the job transport is its own Redis, and it goes down on its own schedule) leaves a
  # message that will never be asked for again: every retry finds the stored source_id
  # and reports a duplicate. So the duplicate path comes back through here, and this
  # stands down when the bytes are already attached or the fetch has given up.
  def self.fetch_media_for(message, inbound)
    media = media_in(inbound)
    return if media.nil? || message.attachments.any? || message.content_attributes['is_unsupported']

    Whatsapp::Session::MediaFetchJob.perform_later(message, media.to_h, inbound.chat&.to_h)
  end

  # Replaces the placeholder a message left behind with the message itself.
  #
  # A message the backend could not decrypt in time is published as an unsupported
  # placeholder carrying the real message's id, and the message that finally arrives
  # carries that same id -- so it reaches Chatwoot as a duplicate of its own placeholder.
  # The content is the part that was missing, so the content is what is written over, in
  # the row that is already there: the bubble the agent is looking at becomes the message,
  # keeping its id, its place in the thread, and anything that quotes it.
  #
  # Answers whether it did, because a caller it says no to still has a duplicate to report.
  def reconcile(message)
    written = false
    # Under the row lock and off the row the lock reloads, which is what every other
    # writer of this flag does (`Message#update_under_lock!`). `content_attributes` is
    # one JSON column: a revoke or a media failure landing between the read and the save
    # would be written away by a merge computed off the stale hash, and the eligibility
    # that was true a moment ago is exactly what such a write would have changed.
    message.with_lock do
      next unless reconcilable?(message)

      written = content_type == 'contacts' ? reconcile_as_a_share(message) : reconcile_in_place(message)
    end
    return false unless written

    # After the save, as on the writing path: the job takes the row by reference and a
    # save that raised would have it fetch bytes for content nobody stored.
    enqueue_media_fetch(message)
    true
  end

  def reconcile_in_place(message)
    # An edit reached the row before the recovery did, and it is the newer body: the one
    # this message carries is the text that edit superseded. Everything around the body
    # is still only here, so the row takes that and keeps what it is showing.
    unless message.is_edited
      message.content = message_content
      attach_location(message)
    end
    settle(message)
    message.save!
    true
  end

  # A share of one contact becomes that contact, in the row that is already there.
  #
  # A share of several does not, and the reason is that the row is not the only thing a
  # message leaves behind. Chatwoot already ran this message's arrival when the
  # placeholder landed: it reopened the conversation, moved `waiting_since`, fired the
  # automations and the notifications. Writing the extra cards as new inbound rows runs
  # all of that a second time, so a conversation an agent resolved while the message was
  # late reopens itself, and the rules fire again on a message from an hour ago.
  #
  # Backdating them to the placeholder is what makes the thread read right and is also
  # what makes them unreachable: `MessageFinder` takes the latest page by `created_at`
  # and pages backwards by `id < before_id`, so a row with a fresh id and an old
  # timestamp falls out of both once twenty newer messages exist. Not backdating them
  # splits one share between its own place in the thread and the bottom of it.
  #
  # So the several-card share stays the unsupported bubble it already was, which is what
  # it was before any of this, and #488 carries what the way out would have to solve.
  #
  # A share whose cards say nothing readable is not a recovery either: `perform` stores
  # exactly the unsupported bubble for that, and this row already is one.
  def reconcile_as_a_share(message)
    cards = Array(content.contacts).select { |card| Whatsapp::Session::Inbound::ContactCard.readable?(card) }
    return false unless cards.one?
    return false unless apply_contact_card(message, cards.first)

    settle(message)
    message.save!
    true
  end

  # What the recovery settles about the row regardless of shape: the attributes the
  # message carried, and the marker that said the row was still waiting for one.
  #
  # `rich` is left out for a row an edit already settled. It describes the body, and the
  # body is not this message's to describe any more: a card drawn around text the edit
  # replaced reads worse than no card. Everything else here is about the message's place
  # rather than its content, which an edit of the body does not move.
  def settle(message)
    recovered = content_attributes.stringify_keys
    recovered = recovered.except('rich') if message.is_edited
    recovered['external_author'] = every_alias_seen(message, recovered['external_author'])

    message.content_attributes = message.content_attributes.merge(recovered.compact)
                                        .except('is_unsupported', 'unsupported_reason')
  end

  # The union of what the placeholder was told and what the message itself carries. The
  # contract lets each of them name the author by one alias, and they need not be the
  # same one, so a plain merge of the two hashes would drop whichever the recovery did
  # not repeat -- and a later deletion naming that one would be back to asking the
  # contact, which is the question this field exists to stop asking.
  def every_alias_seen(message, recovered)
    seen = message.content_attributes['external_author'].to_h.merge(recovered.to_h)

    seen.compact.presence
  end

  def perform
    return build_contact_messages if content_type == 'contacts'

    message = conversation.messages.build(content: message_content, **message_attributes)
    attach_location(message)
    message.save!
    enqueue_media_fetch(message)
    acknowledge([message])
    message
  end

  private

  def inbox = conversation.inbox
  def content = inbound.content
  def incoming? = inbound.incoming?

  # The kind of content, as the string the contract names it by. Never as a class: a
  # class captured before a reload no longer matches the payload's own, and every branch
  # below would fall through in silence.
  def content_type = content&.wire_type

  def message_attributes
    {
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: inbound.id,
      sender: incoming? ? sender : nil,
      message_type: incoming? ? :incoming : :outgoing,
      # WhatsApp already has an echo: it is the phone reporting what it sent. Leaving it
      # at the default `sent` would show the agent a message stuck on one tick that no
      # receipt is ever going to move.
      status: incoming? ? :sent : :delivered,
      content_attributes: content_attributes
    }
  end

  def message_content
    case content_type
    when 'text' then convert_mentions(content.body)
    when 'media' then content.caption
    when 'rich' then content.preview_text
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
      # Who WhatsApp says wrote this, kept as WhatsApp names them rather than as whichever
      # contact row happens to hold them today. A deletion's key names an author and the
      # comparison has to survive an agent editing the contact's phone or a merge
      # rewriting it, both of which move what the contact answers to without moving who
      # wrote the message.
      external_author: author_identity,
      in_reply_to_external_id: inbound.quoted_id.presence,
      referral: inbound.referral.presence,
      is_unsupported: (true if unsupported?),
      # Why there is no body, which is what says whether the message can still turn up.
      # `is_unsupported` cannot: a media download that gave up raises the same flag on a
      # message that arrived perfectly well.
      unsupported_reason: (content.reason if content_type == 'unsupported'),
      rich: (content.to_content_attribute if content_type == 'rich')
    }.compact
  end

  # The reasons a message may still arrive under the id its placeholder was published
  # with. `unknown_type` and `masked` are not among them: the first is a body that did
  # arrive and this build has no arm for, and the second is one WhatsApp withholds from
  # every linked device on purpose.
  #
  # `unavailable` is here because it is the one that recovers on its own: WhatsApp answers
  # a companion device that way for a view-once photo and asks the primary phone to
  # forward it. It is also not in `Content::Unsupported::REASONS`, which is a dead
  # constant the connector has moved past -- #490 carries the sync.
  RECOVERABLE = %w[undecryptable unavailable].freeze

  # Only a placeholder is replaced, and only by something that is not one.
  #
  # Read from the reason and not from `is_unsupported`, because that flag answers a
  # different question: `MediaFetchJob#give_up`, `MediaDownloadFailed` and the outbound
  # sender all raise it on messages that arrived intact, and writing content over one of
  # those would clear a failure the agent is looking at and ask for the bytes again.
  #
  # An edit that landed first takes the marker off the row (`MessageEdited#apply`), which
  # is what stops a delayed recovery from writing the original body over an edit of it.
  # It also costs that recovery the metadata only it carries, the quoted link and the
  # rich attributes -- not the attribution, which the caller records either way. #492.
  #
  def reconcilable?(message)
    RECOVERABLE.include?(message.content_attributes['unsupported_reason']) &&
      content.present? && !unsupported?
  end

  # Both namespaces, because WhatsApp names the same person by phone in one event and by
  # LID in the next, and a reader has to be able to answer in whichever the question
  # arrives in. Absent when the event named nobody, which a direct chat's own message can
  # be: there the chat is the author and nothing else has to say so.
  def author_identity
    party = inbound.sender
    return if party.blank?

    { 'phone' => party.phone, 'lid' => party.lid }.compact.presence
  end

  # A rich card with no text and no media header renders as an empty bubble, which is
  # what the unsupported flag exists for.
  def unsupported?
    return true if content_type == 'unsupported'

    content_type == 'rich' && content.preview_text.blank? && content.media.blank?
  end

  def convert_mentions(text)
    return text if text.blank? || inbound.mentions.blank?

    Whatsapp::MentionConverterService.convert_incoming_mentions(
      text, { mentionedJid: Array(inbound.mentions).map(&:to_jid) }, inbox.account, inbox
    )
  end

  # Location carries no downloadable bytes: the coordinates are the attachment.
  def attach_location(message)
    return unless content_type == 'location'

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
    self.class.fetch_media_for(message, inbound)
  end

  # One message per shared contact, each with a native contact attachment, so the
  # dashboard renders them in the contact bubble instead of as plain text.
  # One transaction for the whole share, as the Cloud path wraps its own message
  # creation: a card failing to save after its siblings were committed would leave the
  # event's source id stored, and the redelivery would then be read as a duplicate and
  # drop the cards that never landed.
  def build_contact_messages
    messages = ActiveRecord::Base.transaction do
      Array(content.contacts).filter_map { |card| build_contact_message(card) }
    end
    return acknowledge(messages).last if messages.present?

    unsupported_contact_message
  end

  # Tells WhatsApp the message was received, which is what puts the second tick on the
  # contact's screen and, when the inbox asks for it, marks the chat read. The Baileys
  # and Z-API writers both do this for every incoming row; without it every message this
  # layer stores stays unread on the contact's phone forever.
  def acknowledge(messages)
    return messages unless incoming? && messages.present?

    inbox.channel.received_messages(messages, conversation)
    messages
  rescue Whatsapp::Session::Errors::NotSupported
    # The backend cannot acknowledge, or has not shipped yet. Storing the message is what
    # matters; the tick on the contact's screen is not worth failing the event over.
    messages
  end

  # An empty share, or one whose cards carry no name, no phone and no vCard, leaves
  # nothing to render, but the conversation has already been opened by the caller and
  # nothing would hold the inbound source id: the thread would sit empty and every
  # redelivery would walk the same path again. The unsupported bubble is what the agent
  # should see anyway, and storing it is what closes the deduplication.
  def unsupported_contact_message
    attributes = message_attributes
    attributes[:content_attributes] = attributes[:content_attributes].merge(is_unsupported: true)
    message = conversation.messages.create!(content: nil, **attributes)
    acknowledge([message])
    message
  end

  def build_contact_message(card)
    message = apply_contact_card(conversation.messages.build(**message_attributes), card)
    return if message.nil?

    message.save!
    message
  end

  # Fills a row, new or already stored, with one card. Answers nil for a card that says
  # nothing, which is what keeps an empty one from taking a row.
  def apply_contact_card(message, card)
    card = card.to_h.stringify_keys
    # `display_name` is what the contract calls it. Reading `name` found nothing, so a
    # card with a phone lost its name and a name-only card was dropped entirely, leaving
    # the conversation that had just been opened with no message in it. Both fields are
    # optional on the wire and a card may arrive as nothing but its vCard, which is why
    # that is read too rather than dropping the share.
    phone = card['phone'].presence || Whatsapp::Session::Inbound::ContactCard.phone_in(card['vcard'])
    name = card['display_name'].presence || Whatsapp::Session::Inbound::ContactCard.name_in(card['vcard'])
    return if phone.blank? && name.blank?

    message.content = Whatsapp::Session::Inbound::ContactCard.line(name, phone)
    message.attachments.build(
      account_id: inbox.account_id, file_type: :contact,
      fallback_title: phone || name, meta: { firstName: name }.compact
    )
    message
  end
end
