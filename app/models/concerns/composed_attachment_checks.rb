# What an attachment is refused for when we compose the message it travels in and are about to
# send it. Off by default on purpose: only those paths turn `refuse_empty_file` on, because a
# refusal on an ingested attachment raises inside the provider webhook and loses the whole message
# instead of storing an odd one. The flag lives in memory only, so reloading a row stored before a
# check existed never refuses it later.
module ComposedAttachmentChecks
  extend ActiveSupport::Concern

  included do
    attr_accessor :refuse_empty_file

    validate :file_is_not_empty, if: :refuse_empty_file
    validate :video_note_carries_no_caption, if: :refuse_empty_file
  end

  private

  # Separate from `acceptable_file`, which runs only on a web widget inbox: which *types* an inbox
  # accepts is a per-channel policy, while a file with no bytes is useless on every channel.
  def file_is_not_empty
    return unless file.attached? && file.byte_size.to_i.zero?

    errors.add(:file, 'is empty')
  end

  # The circle has nowhere to show a caption, and the connector refuses one. Refused when the
  # message is stored, so the caller hears a 422 instead of seeing the message turn red later.
  def video_note_carries_no_caption
    return unless video_note? && message&.content.present?

    errors.add(:base, 'a video note carries no caption: send the text as its own message')
  end
end
