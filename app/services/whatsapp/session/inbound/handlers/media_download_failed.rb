# The provider could not decrypt or download the media of a message it already
# delivered. The message stays, flagged so the agent knows the attachment is gone
# rather than still loading.
class Whatsapp::Session::Inbound::Handlers::MediaDownloadFailed < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    message = find_message(payload.message_id)
    return :ignored if message.nil?
    return :ignored if message.attachments.any?

    # `is_unsupported` lives in the content_attributes JSON, so writing it off the
    # instance loaded before a revoke landed would rewrite the whole hash and undelete
    # the message.
    message.update_under_lock!(is_unsupported: true)
    Rails.logger.warn("[WHATSAPP SESSION] media download failed for #{payload.message_id}: #{payload.reason}")
    :handled
  end
end
