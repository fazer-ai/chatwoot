# Downloads the bytes of an inbound media message and attaches them.
#
# Separate from the message row on purpose: the connector's consumer thread keeps a
# session's events in order, and a multi-megabyte download must not hold it. The
# message is created first and gains its attachment seconds later.
class Whatsapp::Session::MediaFetchJob < ApplicationJob
  queue_as :medium

  retry_on Down::Error, wait: :polynomially_longer, attempts: 3
  retry_on Whatsapp::Session::Errors::ProviderUnavailable, wait: :polynomially_longer, attempts: 3

  # `content` is a serialized Model::Content::Media.
  def perform(message, content)
    return if message.attachments.any?

    media = Whatsapp::Session::Model::Content.from_h(content)
    payload = message.inbox.channel.provider_service.download_media(media.ref)
    attach(message, media, payload)
  rescue Whatsapp::Session::Errors::MediaUnavailable, Whatsapp::Session::Errors::NotSupported => e
    # The provider no longer has the bytes: nothing to retry, and the agent needs to
    # see that the attachment is gone rather than perpetually loading.
    Rails.logger.warn("[WHATSAPP SESSION] media unavailable for message #{message.id}: #{e.message}")
    message.update!(is_unsupported: true)
  end

  private

  def attach(message, media, payload)
    attachment = message.attachments.build(
      account_id: message.account_id,
      file_type: media.attachment_file_type,
      file: { io: payload.io, filename: filename(media, payload, message), content_type: payload.mime || media.mime }
    )
    attachment.meta = { is_recorded_audio: true } if media.voice_note
    message.save!
  end

  def filename(media, payload, message)
    return media.filename if media.filename.present?
    return payload.filename if payload.filename.present?

    mime = (payload.mime || media.mime).to_s
    extension = ".#{mime.split(';').first.split('/').last}" if mime.present?
    "#{media.kind}_#{message.source_id}_#{Time.current.strftime('%Y%m%d')}#{extension}"
  end
end
