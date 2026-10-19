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

  # Recorded as the voice agent's from the start: its ringing message would otherwise put a card
  # on the agents' screens for the moment before the voice agent answers. Taken off when the call
  # is handed to them.
  def recorded_meta = { 'voice_agent' => true }

  # A failure the connector answered before the answer was recorded is this call not taken by
  # the voice agent, and the agents are rung for it as if none was set, when it was offered with
  # a browser's half to answer it with. Answered under the
  # call's lock, read afresh: the call's message offers to join it while it rings, and a call
  # somebody joined or that ended meanwhile is not the voice agent's. Taken, it is announced the
  # way an agent's answer is, which drops the ringing card that message put on every screen.
  def broadcast_incoming(call, sdp_offer)
    url = self.class.stream_url(inbox.channel.ai_voice_stream_url, call: call, direction: 'inbound')
    answered = call.with_lock do
      next true unless call.ringing?
      next false unless inbox.channel.provider_service.accept_call(call.provider_call_id, nil, stream_url: url)

      update_call!(call, 'in_progress', started_at: Time.current, meta: call.meta.merge('rung' => true, 'ai_voice' => true))
      call.broadcast_voice_call_event(:accepted)
      schedule_expiry(call, wait: VOICE_AGENT_CALL_EXPIRY)
      true
    end
    return if answered
    return give_up_unanswerable(call) if sdp_offer.blank?

    call.with_lock { update_call!(call, 'ringing', meta: call.meta.except('voice_agent')) }
    super
  end
end
