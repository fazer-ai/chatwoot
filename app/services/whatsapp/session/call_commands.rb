# Which call a fire-and-forget call command was about. `command.failed` names the command
# and not the call, so a failed answer can only be put back on its call through this.
#
# The failure can be read before the request that published the command gets to write
# down which call it was for: the connector refuses some commands at once. So both sides
# claim the same key, and whichever claims it second learns what the first one wrote.
module Whatsapp::Session::CallCommands
  # Comfortably past the deadline the command carries, so a failure that arrives at all
  # arrives while the command is remembered.
  TTL = 2.minutes.to_i
  FAILED = 'failed'.freeze

  # The publishing side. Answers false when the failure was read first: the command did
  # not go through, and the caller says so instead of reporting it carried out.
  def self.remember(command_id, call_id)
    return true if claim(command_id, call_id)

    Redis::Alfred.get(key(command_id)) != FAILED
  end

  # The failure side. Answers the call the command was about when that was written down
  # first, once; nil when the failure is the first word of this command.
  def self.failed(command_id)
    return if command_id.blank? || claim(command_id, FAILED)

    call_id = Redis::Alfred.get(key(command_id))
    return if call_id.nil? || call_id == FAILED

    Redis::Alfred.delete(key(command_id))
    call_id
  end

  def self.claim(command_id, value)
    Redis::Alfred.set(key(command_id), value, nx: true, ex: TTL)
  end

  def self.key(command_id)
    format(Redis::Alfred::WHATSAPP_CONNECTOR_CALL_COMMAND, command_id: command_id)
  end
end
