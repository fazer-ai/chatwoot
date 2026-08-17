# The envelope around an outbound command payload. `reply_to` is set for RPC commands
# (the list the connector pushes the reply to) and `deadline` bounds how long the
# command is still worth executing after it was queued.
class Whatsapp::Session::Model::Command < Data.define(:type, :payload, :id, :sid, :ts, :reply_to, :deadline,
                                                      :idempotency_key)
  include Whatsapp::Session::Model::Serializable

  Commands = Whatsapp::Session::Model::Commands

  class << self
    def build(payload, **attributes)
      new(type: payload.class.wire_type, payload: payload, **attributes)
    end

    def from_frame(frame)
      frame = frame.stringify_keys
      type = frame['type']
      new(
        type: type, payload: Commands.build(type, frame['payload']), id: frame['id'], sid: frame['sid'],
        ts: frame['ts']&.to_i, reply_to: frame['reply_to'], deadline: frame['deadline']&.to_i,
        idempotency_key: frame['idempotency_key']
      )
    end
  end

  def to_frame
    {
      'v' => Whatsapp::Session::PROTOCOL_VERSION, 'id' => id, 'type' => type, 'sid' => sid, 'ts' => ts,
      'reply_to' => reply_to, 'deadline' => deadline, 'idempotency_key' => idempotency_key,
      'payload' => payload.to_h
    }.compact
  end

  def rpc?
    Commands.rpc?(type)
  end
end
