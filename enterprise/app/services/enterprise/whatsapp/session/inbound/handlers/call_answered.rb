module Enterprise::Whatsapp::Session::Inbound::Handlers::CallAnswered
  def perform
    return :ignored if payload.call_id.blank?

    Whatsapp::ConnectorCallService.new(inbox: inbox).answered(payload)
    :handled
  end
end
