# A connector call on an inbox whose calls a voice agent takes. The call is filed exactly as
# Whatsapp::ConnectorCallService files it, and where that one rings the agents' screens this one
# answers it with the voice agent's media stream: the connector carries the call's voice to that
# WebSocket instead of to a browser. The stream URL names the call and its thread, so the voice
# agent knows whom it is talking to and where to report.
class Whatsapp::ConnectorAiCallService < Whatsapp::ConnectorCallService
  # The stored URL with what identifies the call added to its query: the conversation by the
  # display id the API addresses it by, and the call by the id the connector's `start` frame
  # carries too.
  def self.stream_url(base, call:, direction:)
    uri = URI.parse(base)
    query = URI.decode_www_form(uri.query.to_s).to_h.merge(
      'account_id' => call.account_id.to_s, 'inbox_id' => call.inbox_id.to_s,
      'conversation_id' => call.conversation.display_id.to_s, 'direction' => direction,
      'call_id' => call.provider_call_id
    )
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end

  private

  # A failure the connector answered before the answer was recorded is this call not taken by
  # the voice agent, and the agents are rung for it as if none was set.
  def broadcast_incoming(call, sdp_offer)
    url = self.class.stream_url(inbox.channel.ai_voice_stream_url, call: call, direction: 'inbound')
    return super unless inbox.channel.provider_service.accept_call(call.provider_call_id, nil, stream_url: url)

    call.with_lock do
      update_call!(call, 'in_progress', started_at: Time.current, meta: call.meta.merge('rung' => true, 'ai_voice' => true))
    end
  end
end
