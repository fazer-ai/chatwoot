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
    validate :video_note_goes_alone, if: :refuse_empty_file
  end

  private

  # Separate from `acceptable_file`, which runs only on a web widget inbox: which *types* an inbox
  # accepts is a per-channel policy, while a file with no bytes is useless on every channel.
  def file_is_not_empty
    return unless file.attached? && file.byte_size.to_i.zero?

    errors.add(:file, 'is empty')
  end

  # Refused when the message is stored, so the caller hears a 422 instead of seeing the message
  # turn red later. The circle has nowhere to show a caption, and the connector refuses one. And
  # the native channel sends one file per message, the first: a note behind another file would
  # never leave.
  def video_note_goes_alone
    return unless video_note? && message

    # What goes out as the caption, which a survey writes even when the content is blank.
    errors.add(:base, I18n.t('errors.attachments.video_note.with_text')) if message.outgoing_content.present?
    errors.add(:base, I18n.t('errors.attachments.video_note.not_alone')) if message.attachments.size > 1
  end
end
