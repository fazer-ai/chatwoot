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
    payload = message.inbox.channel.session_backend.download_media(download_command(message, media))
    # Re-read under lock, after the download: a deletion that landed while this job was
    # queued or running destroyed the attachments, and attaching now would put the
    # supposedly deleted media back into storage and back on the API.
    message.with_lock do
      next if message.reload.deleted? || message.attachments.any?

      attach(message, media, payload)
      # `MESSAGE_UPDATED` only reaches the open thread, so the conversation card in the
      # list keeps its "no content" preview for a media-only message until something else
      # touches that conversation.
      Whatsapp::Session::Inbound::ChatList.refresh(message.conversation)
    end
  rescue Whatsapp::Session::Errors::MediaUnavailable, Whatsapp::Session::Errors::NotSupported,
         Whatsapp::Session::Errors::MediaTooLarge => e
    # The provider will not hand over these bytes, now or on a retry: it no longer has
    # them, it cannot serve them, or the file is past its size cap. The agent needs to
    # see that the attachment is not coming rather than an bubble that loads forever.
    Rails.logger.warn("[WHATSAPP SESSION] media unavailable for message #{message.id}: #{e.message}")
    # Under lock and off a reloaded row: `is_unsupported` is a content_attributes flag,
    # and a revoke that landed during the download would be rewritten away by this.
    message.update_under_lock!(is_unsupported: true)
  end

  private

  # The ref alone is not enough to ask for a second time: a blob the connector has already
  # dropped is fetched again from the message it came from, so the command carries the
  # message the ref belongs to as well as the ref itself.
  def download_command(message, media)
    Whatsapp::Session::Model::Commands::MessageDownloadMedia.new(
      chat: Whatsapp::Session::Model::Address.for_contact(message.conversation.contact),
      message_id: message.source_id, ref: media.ref
    )
  end

  def attach(message, media, payload)
    attachment = message.attachments.build(
      account_id: message.account_id,
      file_type: media.attachment_file_type,
      file: { io: payload.io, filename: filename(media, payload, message), content_type: payload.mime || media.mime }
    )
    attachment.meta = { is_recorded_audio: true } if media.voice_note
    # Adding an attachment changes no column on the message, and
    # `Message#dispatch_update_event` returns early on an empty `previous_changes`, so
    # nothing would tell the open dashboards that the bubble finally has its file: the
    # agent would keep seeing the empty bubble until a reload. Stamping `updated_at` in
    # the same save is what makes the row dirty enough to broadcast, once, with the
    # attachment already committed.
    message.updated_at = Time.current
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
