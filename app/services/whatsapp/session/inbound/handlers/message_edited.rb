# The contact (or the connected phone) edited a message that is already stored.
class Whatsapp::Session::Inbound::Handlers::MessageEdited < Whatsapp::Session::Inbound::Handlers::Base
  Content = Whatsapp::Session::Model::Content

  def perform
    target = find_message(payload.message_id)
    return :ignored if target.nil?

    content = edited_content
    # nil is a content type this layer cannot render as text; an empty string is a real
    # edit that removed the caption, and dropping it would leave the old one on screen.
    return :ignored if content.nil?

    # The first edit is what the reader wants to compare against, so a second edit does
    # not overwrite the original.
    previous = target.is_edited ? target.previous_content : target.content
    target.update!(content: content, is_edited: true, previous_content: previous)
    inbound::ChatList.refresh(target.conversation)
    :handled
  end

  private

  def edited_content
    case payload.content
    when Content::Text then payload.content.body.to_s
    when Content::Media then payload.content.caption.to_s
    when Content::Rich then payload.content.preview_text.to_s
    end
  end
end
