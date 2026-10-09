# A call on an inbox with voice calling on. With incoming calls turned off it is refused,
# whatever kind of call it is: the connector lets every call ring on such an inbox, so that
# it can still place calls. Otherwise one the connector offered with a WebRTC `sdp` becomes
# a ringing `Call`, the way a Cloud API call does, and any other is the activity line.
module Enterprise::Whatsapp::Session::Inbound::Handlers::CallOffer
  private

  def take_up_call(contact_inbox)
    return unless channel.voice_enabled?

    service = Whatsapp::ConnectorCallService.new(inbox: inbox, contact_inbox: contact_inbox)
    return service.refuse(payload) && nil unless channel.inbound_calls_enabled?
    return if payload.sdp.blank? || payload.video

    service.offer(payload)
    :handled
  end
end
