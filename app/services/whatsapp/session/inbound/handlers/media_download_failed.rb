# The provider could not decrypt or download the media of a message it already
# delivered. The message stays, flagged so the agent knows the attachment is gone
# rather than still loading.
class Whatsapp::Session::Inbound::Handlers::MediaDownloadFailed < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    message = find_message(payload.message_id)
    return :ignored if message.nil?
    return :ignored if message.attachments.any?

    message.update!(is_unsupported: true)
    Rails.logger.warn("[WHATSAPP SESSION] media download failed for #{payload.message_id}: #{payload.reason}")
    :handled
  end
end
