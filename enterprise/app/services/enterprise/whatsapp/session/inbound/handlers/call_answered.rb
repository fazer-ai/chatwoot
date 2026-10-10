module Enterprise::Whatsapp::Session::Inbound::Handlers::CallAnswered
  def perform
    return :ignored if payload.call_id.blank?

    # Timed by when the connector saw it, not by when a backed-up stream got here.
    Whatsapp::ConnectorCallService.new(inbox: inbox).answered(payload, at: event.at)
    :handled
  end
end
