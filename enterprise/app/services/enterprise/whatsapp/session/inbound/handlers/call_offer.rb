# A call this inbox can answer: the connector offered it with a WebRTC `sdp`, and the inbox
# has voice calling on. It becomes a ringing `Call`, the way a Cloud API call does.
module Enterprise::Whatsapp::Session::Inbound::Handlers::CallOffer
  private

  def take_up_call(contact_inbox)
    return if payload.sdp.blank? || payload.video || !channel.voice_enabled?
    return unless Whatsapp::ConnectorCallService.new(inbox: inbox, contact_inbox: contact_inbox).offer(payload)

    :handled
  end
end
