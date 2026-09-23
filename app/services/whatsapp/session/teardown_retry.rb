# Sends again a teardown the connector says it never attempted.
#
# `session.delete` and `session.logout` are published, not called: nothing waits for them,
# and their failures come back later as `command.failed` on the event stream. One answer
# there is a promise rather than a failure. `not_attempted` is the connector certain that
# nothing reached WhatsApp -- the socket was being dialled and the unlink was never called
# -- so the device is still linked on somebody's phone, and the contract tells a client to
# send the same command again. Treated as final it stays linked for good, because the
# credentials that would sign the unlink are the ones a later teardown throws away.
#
# Only that answer. `retryable?` says a retry might answer differently, which is true of
# the whole ProviderUnavailable family and says nothing about whether a teardown is still
# owed: `session_not_found` is retryable by that definition and means the teardown is
# already done.
#
# The answer usually arrives for a session no inbox holds any more (the inbox was
# destroyed or moved to another provider), which is why the consumer hands it here before
# dropping it as an orphan. The one inbox that can still be around is one an operator
# disconnected, and the job checks at send time that nobody has asked to connect it since.
module Whatsapp::Session::TeardownRetry
  TYPES = %w[session.logout session.delete].freeze

  # The same spacing as the LogoutJob, for the same reason: a socket being dialled is
  # usually back within seconds, and one that is not is down for a while.
  WAITS = [30.seconds, 2.minutes, 5.minutes, 15.minutes, 1.hour].freeze

  # How long the count of attempts outlives the last one. Longer than the widest wait, so
  # the count is still there when that attempt's answer comes back, and short enough that
  # a teardown asked for again another day starts over.
  ATTEMPTS_TTL = 2.hours

  class << self
    def teardown?(payload)
      TYPES.include?(payload.command_type)
    end

    # Schedules the teardown again when the failure is the one the contract says to retry.
    # Answers whether it did.
    def consider(event)
      payload = event.payload
      return false unless teardown?(payload) && not_attempted?(payload.error)

      attempt = count_attempt(event.sid, payload.command_type)
      wait = WAITS[attempt - 1]
      return give_up(event.sid, payload.command_type) if wait.nil?

      Rails.logger.info(
        "[WHATSAPP SESSION] #{payload.command_type} for session #{event.sid} was not attempted by the connector; " \
        "sending it again in #{wait.inspect} (attempt #{attempt} of #{WAITS.size})"
      )
      Whatsapp::Session::TeardownRetryJob.set(wait: wait).perform_later(event.sid, payload.command_type)
      true
    end

    # Whether the teardown is still what somebody wants. A session no inbox holds is
    # always owed one. An inbox that is still here is owed one only while it stays as the
    # disconnect left it: pairing again writes `connecting` before it asks for anything,
    # and a quarantined inbox is the LogoutJob's. A check, not a fence, like the LogoutJob's.
    def wanted?(session_id)
      channel = Channel::Whatsapp.where(provider: 'native').where("provider_config->>'session_id' = ?", session_id).first
      return true if channel.nil?

      channel.provider_connection.to_h['connection'] == 'close' && !Whatsapp::Session::ConnectionStateWriter.disowned?(channel)
    end

    # By the route the first one took: the logout on the session's own stream, where its
    # owner reads it at once, and the delete on the control stream, which reaches a session
    # nobody is running. Bounded by runtime alone, as the backend bounds them, because a
    # deadline would refuse a teardown that arrives while the session is between owners.
    def send_again(session_id, command_type)
      client = Whatsapp::Connector::Client.new(session_id)
      commands = Whatsapp::Session::Model::Commands
      runtime = Whatsapp::Session::Backends::Connector::Backend::TEARDOWN_RUNTIME
      id = case command_type
           when 'session.logout' then client.publish(commands::SessionLogout.new, max_runtime: runtime)
           when 'session.delete' then client.control(commands::SessionDelete.new, max_runtime: runtime)
           end
      Rails.logger.info("[WHATSAPP SESSION] #{command_type} sent again for session #{session_id}: #{id}")
    end

    def attempts_key(session_id, command_type)
      "WHATSAPP::SESSION::TEARDOWN_ATTEMPTS::#{session_id}::#{command_type}"
    end

    private

    # Asked of the catalogue, so the code only counts once it maps to its class: a code
    # that degraded to Internal would not be sent again, which is what the catalogue spec
    # exists to catch.
    def not_attempted?(error)
      error.present? && error.to_exception.is_a?(Whatsapp::Session::Errors::NotAttempted)
    end

    def count_attempt(session_id, command_type)
      key = attempts_key(session_id, command_type)
      attempt = Redis::Alfred.incr(key)
      Redis::Alfred.expire(key, ATTEMPTS_TTL.to_i)
      attempt
    end

    def give_up(session_id, command_type)
      Rails.logger.warn(
        "[WHATSAPP SESSION] #{command_type} for session #{session_id} was not attempted #{WAITS.size + 1} times; " \
        'giving up, and the device may still be linked on the phone that paired it'
      )
      false
    end
  end
end
