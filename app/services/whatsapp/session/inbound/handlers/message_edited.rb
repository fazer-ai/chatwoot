# The contact (or the connected phone) edited a message that is already stored.
class Whatsapp::Session::Inbound::Handlers::MessageEdited < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    target = find_message(payload.message_id)
    # Not stored yet, as far as this transport can tell. On an ordered one it never was.
    return :deferred if target.nil?

    content = edited_content
    # nil is a content type this layer cannot render as text; an empty string is a real
    # edit that removed the caption, and dropping it would leave the old one on screen.
    return :ignored if content.nil?

    apply(target, content)
    inbound::ChatList.refresh(target.conversation)
    :handled
  end

  private

  # Both the read and the write happen under the row lock: `is_edited` and
  # `previous_content` live in the content_attributes JSON, so an edit applied off an
  # instance loaded before a concurrent revoke would serialize the pre-revoke hash and
  # bring a deleted message back, and the "what did it say before" read has to see the
  # same row it is about to write.
  def apply(target, content)
    target.with_lock do
      # The first edit is what the reader wants to compare against, so a second edit
      # does not overwrite the original.
      previous = target.is_edited ? target.previous_content : target.content
      target.content_attributes = target.content_attributes.except('is_unsupported') if placeholder?(target)
      target.update!(content: content, is_edited: true, previous_content: previous)
    end
  end

  # An edit is the first readable body a placeholder's row has had, so that row is no
  # longer a message nothing could read: leaving the flag on renders the edit as the
  # unsupported bubble, which shows none of it.
  #
  # The recovery marker stays, though, and the two say different things now: the row has a
  # body and is still missing everything the message carried around it. The delayed
  # recovery reads that and contributes the rest without touching the body an edit of it
  # already settled.
  #
  # Only a placeholder, though. `is_unsupported` also marks media that never arrived, and
  # a new caption is no answer to bytes that are not coming.
  def placeholder?(target)
    target.content_attributes['unsupported_reason'].present?
  end

  # By wire type, not by class: a class captured before a reload stops matching and the
  # edit is dropped without a word.
  def edited_content
    case payload.content&.wire_type
    when 'text' then payload.content.body.to_s
    when 'media' then payload.content.caption.to_s
    when 'rich' then payload.content.preview_text.to_s
    end
  end
end
