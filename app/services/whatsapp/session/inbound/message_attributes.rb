# What a stored row records about the message besides its body: where it came from, who
# WhatsApp says wrote it, what it was quoting, and -- when there is no body -- why.
#
# Extracted from MessageWriter, which had grown past the class-length metric by carrying
# both this and the writing itself. The recovery path reads the same builder, so a
# placeholder that later receives its message settles under exactly the attributes the
# writing path would have given it.
class Whatsapp::Session::Inbound::MessageAttributes
  # Why an imported file has no bytes: the dump carried no reference to them. Not a verdict
  # on the file, so a later delivery of the same message that does carry one fills it in.
  HISTORY_MEDIA = 'history_media'.freeze

  # Unsupported for good, as opposed to an imported file whose reference simply did not
  # come with the dump: that one is still waiting for its bytes.
  def self.given_up?(message)
    attributes = message.content_attributes || {}
    attributes['is_unsupported'].present? && attributes['unsupported_reason'] != HISTORY_MEDIA
  end

  def initialize(inbound:, imported: false)
    @inbound = inbound
    @imported = imported
  end

  def to_h
    origin.merge(body).compact
  end

  # A rich card with no text and no media header renders as an empty bubble, which is
  # what the unsupported flag exists for.
  #
  # So is an imported file that came with no reference to its bytes. On the live path a
  # media message without one is followed by `media.download_failed`, which is what asks
  # for the file again; nothing follows a message out of a history dump, so the row would
  # be a bubble waiting forever for a file nobody is going to fetch.
  def unsupported?
    return true if content_type == 'unsupported'
    return true if imported && unfetchable_media?

    content_type == 'rich' && content.preview_text.blank? && content.media.blank?
  end

  private

  attr_reader :inbound, :imported

  def content = inbound.content
  def content_type = content&.wire_type
  def incoming? = inbound.incoming?

  def unfetchable_media?
    media = Whatsapp::Session::Inbound::MessageWriter.media_in(inbound)
    media.present? && media.ref.blank?
  end

  def origin
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
      # Not the same statement as `external_created_at`, which every session message
      # carries: this one says the row was filed after the fact, which is what a report
      # excluding backfilled traffic, or a bubble explaining an old date, has to read.
      imported: (true if imported)
    }
  end

  # What the row says about a body it does not have, and what a later fetch would need to
  # build the attachment the body was.
  def body
    {
      is_unsupported: (true if unsupported?),
      # Why there is no body, which is what says whether the message can still turn up.
      # `is_unsupported` cannot: a media download that gave up raises the same flag on a
      # message that arrived perfectly well.
      unsupported_reason: unsupported_reason,
      pending_media: pending_media,
      rich: (content.to_content_attribute if content_type == 'rich')
    }
  end

  def unsupported_reason
    return content.reason if content_type == 'unsupported'

    HISTORY_MEDIA if imported && unfetchable_media?
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

  # What the file was, for a media message whose bytes did not come with it.
  #
  # The provider says on the `media.download_failed` that follows whether they can still
  # be fetched, and by then this row is the only place the file's own description
  # survives: the event that carried it does not come again, and there is no attachment
  # to read it off. Without it a recoverable file could be asked for and then not
  # attached, because nothing would know what kind of attachment to build.
  #
  # Only what a later fetch reads. The caption is already this message's content and the
  # preview is a data URI worth kilobytes, so neither is copied into a column nothing
  # renders from.
  def pending_media
    media = Whatsapp::Session::Inbound::MessageWriter.media_in(inbound)
    return if media.nil? || media.ref.present?

    Whatsapp::Session::Model::Content::Media.new(
      kind: media.kind, mime: media.mime, filename: media.filename, voice_note: media.voice_note
    ).to_h
  end
end
