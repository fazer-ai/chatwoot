# A call.accept the connector could not carry out: the call it answered is closed as failed.
module Enterprise::Whatsapp::Session::Inbound::Handlers::CommandFailed
  private

  def call_command_failed
    return :ignored unless payload.command_type == 'call.accept'

    call_id = Whatsapp::Session::CallCommands.failed(payload.command_id)
    return :ignored if call_id.nil?

    # Let go only once the call is closed: a failure that did not apply is applied again
    # when the stream delivers it again.
    Whatsapp::ConnectorCallService.new(inbox: inbox).accept_failed(call_id)
    Whatsapp::Session::CallCommands.settled(payload.command_id)
    :handled
  end
end
