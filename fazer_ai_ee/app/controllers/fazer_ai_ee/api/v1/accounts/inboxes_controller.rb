module FazerAiEe::Api::V1::Accounts::InboxesController
  # Live, not in the cached inbox payload: a redeploy that opens the call port writes no inbox row.
  def whatsapp_calling_status
    render json: { voice_calls_carried: @inbox.channel.voice_calls_carried? } if ensure_whatsapp_calling_supported
  end
end
