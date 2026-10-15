# Which call a fire-and-forget call command was about. `command.failed` names the command
# and not the call, so a failed answer can only be put back on its call through this, and a
# failed refusal or hang-up can only be sent again through it: what a refusal names as the
# caller and how many times it was already sent travel with it.
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

  # What was written down about one command: `from` only for a refusal, `attempt` counting
  # from 0 for the first time it went out.
  Remembered = Data.define(:call_id, :from, :attempt)

  # The publishing side. Answers false when the failure was read first: the command did
  # not go through, and the caller says so instead of reporting it carried out.
  def self.remember(command_id, call_id, from: nil, attempt: 0)
    return true if claim(command_id, { call_id: call_id, from: from&.to_h, attempt: attempt }.compact.to_json)

    Redis::Alfred.get(key(command_id)) != FAILED
  end

  # The failure side. Answers what the command was about when that was written down first;
  # nil when the failure is the first word of this command. Answered again for the same
  # failure delivered again, until `settled` says it was carried out.
  def self.failed(command_id)
    return if command_id.blank? || claim(command_id, FAILED)

    value = Redis::Alfred.get(key(command_id))
    return if value.nil? || value == FAILED

    fields = JSON.parse(value)
    Remembered.new(call_id: fields['call_id'], from: fields['from'], attempt: fields['attempt'].to_i)
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
