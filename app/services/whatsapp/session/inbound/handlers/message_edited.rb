# The contact (or the connected phone) edited a message that is already stored.
class Whatsapp::Session::Inbound::Handlers::MessageEdited < Whatsapp::Session::Inbound::Handlers::Base
  Content = Whatsapp::Session::Model::Content

  def perform
    target = find_message(payload.message_id)
    return :ignored if target.nil?

    content = edited_content
    return :ignored if content.blank?

    # The first edit is what the reader wants to compare against, so a second edit does
    # not overwrite the original.
    previous = target.is_edited ? target.previous_content : target.content
    target.update!(content: content, is_edited: true, previous_content: previous)
    :handled
  end

  private

  def edited_content
    case payload.content
    when Content::Text then payload.content.body
    when Content::Media then payload.content.caption
    when Content::Rich then payload.content.preview_text
    end
  end
end
