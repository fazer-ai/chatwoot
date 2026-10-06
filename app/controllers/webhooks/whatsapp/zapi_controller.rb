# Where a Z-API instance delivers its events once Whatsapp::Providers::WhatsappZapiService has
# registered this URL. Z-API signs nothing and echoes no secret in the body, so the token in
# the path is the only credential. Everything after it is the generic route's, which is why
# the request is handed back to that controller dressed as one of its own.
#
# An unknown channel and a wrong token answer the same 401, so the route says nothing about
# which inboxes exist.
class Webhooks::Whatsapp::ZapiController < Webhooks::WhatsappController
  skip_before_action :verify_meta_signature!, :verify_provider_token!
  before_action :authenticate_webhook_token!

  private

  def authenticate_webhook_token!
    return head :unauthorized unless whatsapp_channel && matches_webhook_verify_token?(params[:webhook_token])

    # The token has done its job, and left in it would ride along into the job's arguments.
    # `object` goes too: the job reads it as a Cloud payload and picks the inbox from the
    # body, which would let this inbox's token speak for another one.
    params.delete(:webhook_token)
    params.delete(:channel_id)
    params.delete(:object)
    params[:phone_number] = whatsapp_channel.phone_number
    Whatsapp::Providers::WhatsappZapiService.new(whatsapp_channel: whatsapp_channel).confirm_webhook_url
  end

  def whatsapp_channel
    @whatsapp_channel ||= Channel::Whatsapp.find_by(id: params[:channel_id], provider: 'zapi')
  end
end
