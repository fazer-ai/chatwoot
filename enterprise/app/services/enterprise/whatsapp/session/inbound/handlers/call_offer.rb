# A call on an inbox with voice calling on. One the connector offered with a WebRTC `sdp`
# becomes a ringing `Call`, the way a Cloud API call does, and any other is the activity line.
#
# With incoming calls turned off nothing rings here and nothing is refused: a refusal from a
# linked device ends the call on every device of the account, the phone included (#850), so
# the call rings on the phone and is the activity line.
module Enterprise::Whatsapp::Session::Inbound::Handlers::CallOffer
  private

  def take_up_call(contact_inbox)
    return unless channel.voice_enabled? && channel.inbound_calls_enabled?
    return if payload.sdp.blank? || payload.video

    service = Whatsapp::ConnectorCallService.new(inbox: inbox, contact_inbox: contact_inbox)
    return if service.internal_call?(payload.from, payload.call_id)

    service.offer(payload)
    :handled
  end
end
