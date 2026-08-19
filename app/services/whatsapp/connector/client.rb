# Talks to the connector over Redis: publishes commands, waits for RPC answers, and
# reads the registry that says whether anyone is listening.
#
# One client is one session. It uses its own connection pool rather than $alfred: that
# pool is namespaced under `alfred:`, and these keys belong to another process.
class Whatsapp::Connector::Client
  Model = Whatsapp::Session::Model
  Errors = Whatsapp::Session::Errors

  # A command stream is drained by its owner as fast as the session can execute; the cap
  # is a backstop against an owner that disappeared, not a working size.
  COMMAND_STREAM_MAXLEN = 1_000
  # How long an RPC waits before giving up. The deadline sent with the command is a
  # little shorter, so the connector stops working on it before the caller stops caring.
  RPC_TIMEOUT = 20
  DEADLINE_MARGIN = 2
  REPLY_TTL = 60
  # A connector heartbeat older than this means nobody is holding the sessions.
  INSTANCE_TTL = 60

  class << self
    def pool
      @pool ||= ConnectionPool.new(size: ENV.fetch('WHATSAPP_CONNECTOR_REDIS_POOL', 5).to_i, timeout: 2) do
        Redis.new(Redis::Config.app.merge(timeout: RPC_TIMEOUT + 5))
      end
    end

    # Specs and the consumer's shard workers need their own connections.
    def reset_pool!
      @pool = nil
    end

    def with_redis(&)
      pool.with(&)
    end
  end

  attr_reader :session_id

  def initialize(session_id)
    @session_id = session_id
  end

  # Fire and forget: the command is queued for the session's owner. Failures come back
  # later as a command.failed event.
  def publish(payload, idempotency_key: nil)
    command = build(payload, idempotency_key: idempotency_key)
    write(command_stream, command)
    command.id
  end

  # Queues the command and waits for the answer the owner pushes back.
  def call(payload, timeout: RPC_TIMEOUT, idempotency_key: nil)
    ensure_available!
    command = build(payload, idempotency_key: idempotency_key, reply_to: true, timeout: timeout)
    write(command_stream, command)
    await(command, timeout)
  end

  # Session-agnostic commands (wake, ping): any live instance answers.
  def control(payload, timeout: RPC_TIMEOUT)
    command = build(payload, reply_to: Model::Commands.rpc?(payload.class.wire_type), timeout: timeout)
    write(Whatsapp::Connector.key('control'), command)
    return command.id unless command.reply_to

    await(command, timeout)
  end

  # Live connector instances and what they advertise (version, protocol range, media
  # endpoint). Their keys expire on their own, so what is here is what is alive.
  def instances
    self.class.with_redis do |redis|
      redis.smembers(Whatsapp::Connector.key('instances')).filter_map do |id|
        instance = redis.hgetall(Whatsapp::Connector.key('instance', id))
        instance.presence
      end
    end
  end

  def available?
    instances.any?
  end

  # Both sides serve a range of protocol majors; they can talk when the ranges overlap.
  def compatible?
    instances.any? { |instance| speaks_our_protocol?(instance) }
  end

  # The bearer token a blob URL is served with. Each instance publishes its own and only
  # accepts that one, and a blob lives on the instance that downloaded it, so the token
  # has to be picked by the URL rather than by whichever instance the registry lists
  # first. Falling back to any of them covers a URL served from somewhere else entirely.
  def media_token(url)
    live = instances
    owner = live.find do |instance|
      advertised = instance['advertise_url'].presence
      advertised && url.to_s.start_with?(advertised)
    end
    (owner || live.first)&.dig('media_token').presence
  end

  private

  def command_stream
    Whatsapp::Connector.key('cmd', session_id)
  end

  def build(payload, idempotency_key: nil, reply_to: false, timeout: RPC_TIMEOUT)
    id = SecureRandom.uuid
    now = (Time.current.to_f * 1000).round
    attributes = { id: id, sid: session_id, ts: now, idempotency_key: idempotency_key }
    if reply_to
      attributes[:reply_to] = reply_key(id)
      attributes[:deadline] = now + ((timeout - DEADLINE_MARGIN) * 1000)
    end
    Model::Command.build(payload, **attributes)
  end

  def reply_key(command_id)
    Whatsapp::Connector.key('reply', command_id)
  end

  def write(stream, command)
    fields = command.to_frame.transform_values { |value| value.is_a?(String) ? value : value.to_json }
    self.class.with_redis do |redis|
      redis.xadd(stream, fields, maxlen: COMMAND_STREAM_MAXLEN, approximate: true)
    end
  end

  def await(command, timeout)
    raw = self.class.with_redis { |redis| redis.blpop(command.reply_to, timeout: timeout) }
    raise Errors::Timeout, "no answer to #{command.type} within #{timeout}s" if raw.nil?

    reply = JSON.parse(raw.last)
    raise error_for(reply) unless reply['ok']

    reply['result']
  rescue JSON::ParserError => e
    raise Errors::Internal, "malformed reply to #{command.type}: #{e.message}"
  end

  def error_for(reply)
    error = reply['error'] || {}
    Errors.build(error['code'], error['message'])
  end

  def speaks_our_protocol?(instance)
    min = instance['protocol_min'].to_i
    max = instance['protocol_max'].to_i
    max.positive? && Whatsapp::Session::PROTOCOL_VERSION.between?(min, max)
  end

  # A command sent with nobody listening would sit in the stream until it expired, and
  # the agent would watch a message hang as "sending" for the whole deadline. A connector
  # that is running but has moved past this protocol is the same thing with a step in
  # between: it reads the frame, does not recognize the version, and drops it. Refusing
  # here is what turns both into an error the agent can see.
  def ensure_available!
    live = instances
    raise Errors::ProviderUnavailable, 'no whatsapp connector is running' if live.empty?
    return if live.any? { |instance| speaks_our_protocol?(instance) }

    raise Errors::ProviderUnavailable, "no whatsapp connector speaks protocol #{Whatsapp::Session::PROTOCOL_VERSION}"
  end
end
