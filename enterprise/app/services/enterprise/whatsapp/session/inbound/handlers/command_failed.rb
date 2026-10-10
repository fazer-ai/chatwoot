# A call command the connector could not carry out. A failed answer closes its call as
# failed; a failed refusal or hang-up was already applied here, so it is sent again while
# a retry can still answer differently.
module Enterprise::Whatsapp::Session::Inbound::Handlers::CommandFailed
  RETRIED_CALL_COMMANDS = %w[call.reject call.terminate].freeze

  private

  def call_command_failed
    type = payload.command_type
    return :ignored unless type == 'call.accept' || RETRIED_CALL_COMMANDS.include?(type)

    command = Whatsapp::Session::CallCommands.failed(payload.command_id)
    return :ignored if command.nil?

    # Let go only once the failure is applied: one that did not apply is applied again
    # when the stream delivers it again.
    if type == 'call.accept'
      Whatsapp::ConnectorCallService.new(inbox: inbox).accept_failed(command.call_id)
    else
      Whatsapp::CallCommandRetryJob.consider(inbox, type, payload.error, command)
    end
    Whatsapp::Session::CallCommands.settled(payload.command_id)
    :handled
  end
end
