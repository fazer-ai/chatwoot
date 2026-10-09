# Which call a fire-and-forget call command was about. `command.failed` names the command
# and not the call, so a failed answer can only be put back on its call through this.
module Whatsapp::Session::CallCommands
  # Comfortably past the deadline the command carries, so a failure that arrives at all
  # arrives while the command is remembered.
  TTL = 2.minutes

  def self.remember(command_id, call_id)
    Redis::Alfred.setex(key(command_id), call_id, TTL)
  end

  # The call the command was about, once: a redelivered failure finds nothing.
  def self.take(command_id)
    return if command_id.blank?

    call_id = Redis::Alfred.get(key(command_id))
    Redis::Alfred.delete(key(command_id)) if call_id
    call_id
  end

  def self.key(command_id)
    format(Redis::Alfred::WHATSAPP_CONNECTOR_CALL_COMMAND, command_id: command_id)
  end
end
