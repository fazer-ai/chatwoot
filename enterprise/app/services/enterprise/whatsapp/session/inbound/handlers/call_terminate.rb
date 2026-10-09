module Enterprise::Whatsapp::Session::Inbound::Handlers::CallTerminate
  def perform
    return :ignored if payload.call_id.blank?

    Whatsapp::ConnectorCallService.new(inbox: inbox).terminate(payload)
    :handled
  end
end
