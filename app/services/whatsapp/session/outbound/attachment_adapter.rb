# Turns a Chatwoot attachment into canonical media content.
#
# The bytes are not read here: the provider is given a URL and fetches them itself.
# That keeps a 60 MB video out of the Rails process and out of the command frame, and
# it is why an inbox behind a private network needs INTERNAL_HOST_URL to point at
# something the provider can actually reach.
class Whatsapp::Session::Outbound::AttachmentAdapter
  # Chatwoot's file_type enum, in the terms the WhatsApp protocol uses.
  KINDS = { 'image' => 'image', 'audio' => 'audio', 'video' => 'video', 'file' => 'document' }.freeze

  attr_reader :attachment, :caption

  def initialize(attachment, caption: nil)
    @attachment = attachment
    @caption = caption
  end

  # Resolved per call rather than aliased: a constant pointing at another file's class
  # keeps the pre-reload object, and in development that object is the one Zeitwerk
  # already discarded.
  def content = Whatsapp::Session::Model::Content
  def media_ref = Whatsapp::Session::Model::MediaRef

  def perform
    return if attachment.blank? || !attachment.file.attached?

    file = attachment.file
    content::Media.new(
      kind: kind, mime: file.content_type, filename: file.filename.to_s, caption: caption.presence,
      voice_note: voice_note?, size: file.byte_size,
      ref: media_ref.url(attachment.download_url, mime: file.content_type, size: file.byte_size)
    )
  end

  private

  # A sticker is stored as an image with a webp body; WhatsApp needs the distinction.
  def kind
    return 'sticker' if attachment.file.content_type == 'image/webp'

    KINDS.fetch(attachment.file_type, 'document')
  end

  # `is_recorded_audio` is the older fazer.ai key (transcode pipeline and old messages).
  def voice_note?
    meta = attachment.meta || {}
    meta['is_voice_message'].present? || meta['is_recorded_audio'].present?
  end
end
