# Which call a fire-and-forget call command was about. `command.failed` names the command
# and not the call, so a failed answer can only be put back on its call through this.
#
# The failure can be read before the request that published the command gets to write
# down which call it was for: the connector refuses some commands at once. So both sides
# claim the same key, and whichever claims it second learns what the first one wrote.
module Whatsapp::Session::CallCommands
  # Past the deadline the command carries, and past how long a shard can stall before it
  # reads the failure (Whatsapp::Connector::Consumer::ShardWorker::BUSY_WAITS add up to
  # over five minutes), so a failure that arrives at all arrives while the command is
  # remembered. One small key per answer, so a day costs nothing.
  TTL = 1.day.to_i
  FAILED = 'failed'.freeze

  # The publishing side. Answers false when the failure was read first: the command did
  # not go through, and the caller says so instead of reporting it carried out.
  def self.remember(command_id, call_id)
    return true if claim(command_id, call_id)

    Redis::Alfred.get(key(command_id)) != FAILED
  end

  # The failure side. Answers the call the command was about when that was written down
  # first; nil when the failure is the first word of this command. Answered again for the
  # same failure delivered again, until `settled` says it was carried out.
  def self.failed(command_id)
    return if command_id.blank? || claim(command_id, FAILED)

    call_id = Redis::Alfred.get(key(command_id))
    call_id unless call_id.nil? || call_id == FAILED
  end

  # The failure was applied to its call, so a redelivery of it has nothing left to do.
  def self.settled(command_id)
    Redis::Alfred.delete(key(command_id))
  end

  def self.claim(command_id, value)
    Redis::Alfred.set(key(command_id), value, nx: true, ex: TTL)
  end

  def self.key(command_id)
    format(Redis::Alfred::WHATSAPP_CONNECTOR_CALL_COMMAND, command_id: command_id)
  end
end
