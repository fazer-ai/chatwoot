# Owns one event shard: reads it, dispatches what it reads, acknowledges what it
# handled.
#
# The loop is deliberately single threaded and synchronous. Anything heavy that does
# not depend on ordering (downloading media, fetching an avatar) is already a job by
# the time it gets here, so the thread only ever does bookkeeping and database writes.
class Whatsapp::Connector::Consumer::ShardWorker
  Consumer = Whatsapp::Connector::Consumer
  Model = Whatsapp::Session::Model

  # How long an entry may sit unacknowledged before another consumer may take it over:
  # long enough that a slow dispatch is not stolen, short enough that a crashed
  # consumer's backlog moves within a minute.
  IDLE_CLAIM_MS = 60_000
  BLOCK_MS = 5_000
  BATCH = 10
  # How long a cursor outlives the session it belongs to. It only has to outlast what a
  # stream can redeliver, which is bounded by its MAXLEN; the TTL is there so a deleted
  # inbox does not leave a key behind forever.
  CURSOR_TTL = 30.days.to_i

  # Waits between attempts at one entry. A handler that failed on a deadlock or on a
  # connection reset gets a few more passes before the event is parked.
  RETRY_WAITS = [1, 5, 30].freeze
  # Contention on the chat lock is expected rather than exceptional: a group roster sync
  # started from Sidekiq holds it for as long as GROUP_SYNC_LOCK_TTL, and the events of
  # that group have to wait it out. Waiting stalls the shard, which is what ordering
  # costs: skipping ahead would hand the session its events out of order, and there is
  # no way to put one back.
  BUSY_WAITS = [5, 15, 30, 60, 60].freeze
  PAUSE_SLICE = 0.5

  attr_reader :shard, :consumer_id

  def initialize(shard, consumer_id)
    @shard = shard
    @consumer_id = consumer_id
    @stopped = false
  end

  def run
    poll until stopped?
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP CONNECTOR] shard #{shard} died: #{e.class}: #{e.message}")
    ChatwootExceptionTracker.new(e).capture_exception
  ensure
    @redis&.close
  end

  def stop
    @stopped = true
  end

  def stopped?
    @stopped
  end

  # One pass: whatever a dead consumer left behind first, then what is new. Returns the
  # number of entries processed, which is what makes the loop testable without threads.
  def poll
    ensure_group
    claim_orphans + read_new
  end

  private

  def stream = Consumer.shard_key(shard)

  def redis
    @redis ||= Redis.new(Redis::Config.app.merge(timeout: (BLOCK_MS / 1000) + 5))
  end

  # Created at 0 rather than at $: whatever the connector published while no consumer
  # was running is still on the stream, and losing it would lose messages. Replays are
  # harmless, because the cursor already decides what was processed.
  def ensure_group
    redis.xgroup(:create, stream, Consumer::GROUP, '0', mkstream: true)
  rescue Redis::CommandError => e
    # BUSYGROUP: another consumer created it first, which is the normal case.
    raise unless e.message.include?('BUSYGROUP')
  end

  # Entries another consumer read and never acknowledged, because it died holding them.
  def claim_orphans
    claimed = redis.xautoclaim(stream, Consumer::GROUP, consumer_id, IDLE_CLAIM_MS, '0-0', count: BATCH)
    process(claimed['entries'])
  rescue Redis::CommandError => e
    raise unless e.message.include?('NOGROUP')

    ensure_group
    0
  end

  def read_new
    response = redis.xreadgroup(Consumer::GROUP, consumer_id, stream, '>', count: BATCH, block: BLOCK_MS)
    process(response&.dig(stream) || {})
  end

  def process(entries)
    handled = 0
    entries.to_a.each do |entry_id, fields|
      # A worker that lost its shard, or whose process is going away, leaves the rest of
      # the batch alone: the entries stay in this consumer's pending list and whoever
      # takes the shard next claims them by idle time. Acknowledging them unprocessed
      # here would drop the events instead.
      break if stopped?

      handled += 1 if handle(entry_id, fields)
    end
    handled
  end

  def handle(entry_id, fields)
    outcome = deliver(entry_id, fields)
    redis.xack(stream, Consumer::GROUP, entry_id) unless outcome == :abandoned
    outcome == :handled
  end

  # Runs the entry, retrying what a second attempt could fix. Answers :handled, :parked
  # (dead-lettered) or :abandoned (left pending, because this worker is stopping).
  #
  # Each attempt is wrapped in the executor on its own, so the waits between them do not
  # hold an ActiveRecord connection: this is a long-lived thread outside the request
  # cycle, and a connection checked out here is not returned until the wrap closes.
  def deliver(entry_id, fields)
    attempt = 0
    begin
      attempt += 1
      Rails.application.executor.wrap { dispatch(Model::Event.from_frame(decode(fields))) }
      :handled
    rescue Whatsapp::Session::Errors::InvalidEvent, JSON::ParserError => e
      # A frame this build cannot read does not become readable by being read again.
      dead_letter(entry_id, fields, e)
      :parked
    rescue Whatsapp::Session::Inbound::Locks::Busy => e
      outcome = next_outcome(entry_id, fields, e, BUSY_WAITS[attempt - 1])
      retry if outcome == :retry

      outcome
    rescue StandardError => e
      outcome = next_outcome(entry_id, fields, e, RETRY_WAITS[attempt - 1])
      retry if outcome == :retry

      outcome
    end
  end

  def next_outcome(entry_id, fields, error, wait)
    return :abandoned if stopped?

    if wait.nil?
      dead_letter(entry_id, fields, error)
      return :parked
    end

    Rails.logger.warn("[WHATSAPP CONNECTOR] shard #{shard} retrying in #{wait}s: #{error.class}: #{error.message}")
    pause(wait)
    stopped? ? :abandoned : :retry
  end

  # Sliced so that a shutdown does not have to wait out the whole backoff.
  def pause(seconds)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    sleep(PAUSE_SLICE) while !stopped? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  end

  # Every stream field is a string; the payload is the only one carrying JSON.
  def decode(fields)
    fields.merge('payload' => JSON.parse(fields['payload'].presence || '{}'))
  end

  def dispatch(event)
    channel = channel_for(event.sid)
    return if channel.nil?
    return unless fresh?(event)

    Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)
    mark_processed(event)
  end

  def channel_for(session_id)
    return if session_id.blank?

    channel = Channel::Whatsapp.where("provider_config->>'session_id' = ?", session_id).first
    Rails.logger.warn("[WHATSAPP CONNECTOR] no inbox for session #{session_id}") if channel.nil?
    channel
  end

  # A redelivery (this consumer took over a shard mid-flight) must not replay what the
  # previous owner already wrote. Message-level deduplication would catch most of it,
  # but not the events that carry no message.
  def fresh?(event)
    cursor = redis.get(Consumer.cursor_key(event.sid))
    return true if cursor.blank?

    epoch, seq = cursor.split(':').map(&:to_i)
    event.newer_than?([epoch, seq])
  end

  def mark_processed(event)
    redis.set(Consumer.cursor_key(event.sid), event.cursor.join(':'), ex: CURSOR_TTL)
  end

  # Nothing here is worth retrying forever: a payload this build cannot read will not
  # become readable, and blocking the shard on it would stop every session that shares
  # it. The entry is parked where a super admin can look at it and re-run it.
  def dead_letter(entry_id, fields, error)
    Rails.logger.error("[WHATSAPP CONNECTOR] shard #{shard} dropped #{entry_id}: #{error.class}: #{error.message}")
    ChatwootExceptionTracker.new(error).capture_exception
    redis.lpush(Consumer.dlq_key, { 'shard' => shard, 'entry_id' => entry_id, 'fields' => fields,
                                    'error' => "#{error.class}: #{error.message}" }.to_json)
    redis.ltrim(Consumer.dlq_key, 0, 999)
  end
end
