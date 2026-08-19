# Decides which event shards this process reads, and keeps a thread on each of them.
#
# Shards are claimed with a Redis lease, so several Chatwoot processes can run the
# consumer without ever reading the same shard twice. A process that dies stops
# renewing, its leases expire, and the survivors pick the shards up on their next tick.
#
# The lease outlives the worker, never the other way round: a shard is only given back
# once the thread that was reading it has actually exited. Releasing it while a dispatch
# is still running is what would let a peer read the same shard alongside it.
class Whatsapp::Connector::Consumer::Supervisor
  Consumer = Whatsapp::Connector::Consumer
  ShardWorker = Whatsapp::Connector::Consumer::ShardWorker

  # Long enough to survive a slow tick, short enough that a crashed process's shards
  # move within seconds.
  LEASE_TTL = 30
  HEARTBEAT_TTL = 15
  TICK = 5
  # How many consumer heartbeats one SCAN pass walks over. The registry is one key per
  # process, so a single pass covers any realistic deployment; the loop is there because
  # SCAN promises no more than a best effort per call.
  SCAN_BATCH = 100
  # How long a shutdown waits for the workers to come out. They all start winding down
  # together, so this bounds the whole handover rather than each shard. It has to clear
  # ShardWorker::BLOCK_MS, which is how long an idle worker sits in XREADGROUP before it
  # looks at its stop flag, and stay inside the grace period a container manager gives a
  # process before it kills it.
  DRAIN_TIMEOUT = 10

  # Extending a lease this process no longer holds would push another consumer off a
  # shard it is already reading, and deleting one would hand a live shard to a third.
  # Both compare the holder and act in the same round trip so the check cannot go stale
  # between them.
  RENEW_SCRIPT = <<~LUA.freeze
    if redis.call('get', KEYS[1]) == ARGV[1] then
      return redis.call('expire', KEYS[1], ARGV[2])
    end
    return 0
  LUA

  RELEASE_SCRIPT = <<~LUA.freeze
    if redis.call('get', KEYS[1]) == ARGV[1] then
      return redis.call('del', KEYS[1])
    end
    return 0
  LUA

  attr_reader :consumer_id, :workers

  # `worker_class` is injectable so the specs can drive the claim loop without a real
  # stream reader behind it.
  def initialize(consumer_id: nil, worker_class: ShardWorker)
    @consumer_id = consumer_id || "#{Socket.gethostname}-#{Process.pid}"
    @worker_class = worker_class
    @workers = {}
    @threads = {}
    @stopped = false
    @draining = false
    # Sidekiq calls quiet and shutdown from its own thread while the supervisor thread
    # is somewhere inside a tick, and both touch the worker table and the same Redis
    # connection, which is not thread safe.
    @mutex = Mutex.new
  end

  def start
    return if @supervisor_thread&.alive?

    @supervisor_thread = Thread.new do
      until @stopped
        safe_tick
        sleep(TICK)
      end
    end
  end

  # Sidekiq's quiet phase: stop claiming and tell the workers to finish, so a peer can
  # take the shards over before this process goes away. It returns without waiting for
  # them, because Sidekiq runs this before it starts its own shutdown clock; the
  # supervisor thread stays up through the drain, renewing the leases of the workers that
  # are still inside an entry and giving each one back as it exits.
  def quiet
    @draining = true
    @mutex.synchronize { stop_all }
  end

  def stop
    quiet
    @stopped = true
    @supervisor_thread&.join(TICK + 1)
    @supervisor_thread&.kill
    @mutex.synchronize { drain }
  end

  # One pass of the claim loop, which is also what the specs drive directly.
  def tick
    @mutex.synchronize do
      # Twice on purpose: the first announces this consumer so peers count it before it
      # claims anything, the second publishes what it ended up holding.
      heartbeat
      reap
      rebalance
      claim
      renew
      heartbeat
    end
  end

  private

  # A tick that raises must not end the consumer for the life of the process: Redis
  # going away for a moment is the expected reason, and it comes back.
  def safe_tick
    tick
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP CONNECTOR] consumer tick failed: #{e.class}: #{e.message}")
    ChatwootExceptionTracker.new(e).capture_exception
  end

  def redis
    @redis ||= Redis.new(Redis::Config.app)
  end

  # The connector owns the fan-out: it is what decides which stream a session's events go
  # on, and it publishes the count it is using. Reading fewer than it publishes would
  # leave whole streams unconsumed, and the inboxes on them silently deaf, so the local
  # setting is only the answer for an installation whose connector has never run.
  def shards
    (0...advertised_shards).to_a
  end

  def advertised_shards
    configured = Whatsapp::Connector.event_shards
    advertised = redis.hget(Whatsapp::Connector.key('meta'), 'event_shards').to_i
    return configured unless advertised.positive?

    if advertised > configured
      # Following it is still right, but the database pool was sized from the configured
      # number, so the extra threads are reading without connections reserved for them.
      Rails.logger.warn(
        "[WHATSAPP CONNECTOR] the connector publishes #{advertised} event shards, this is configured for " \
        "#{configured}; following the connector, raise WHATSAPP_CONNECTOR_EVENT_SHARDS to match so the " \
        'database pool has room for them'
      )
    elsif advertised < configured
      Rails.logger.warn(
        "[WHATSAPP CONNECTOR] the connector publishes #{advertised} event shards, this is configured for " \
        "#{configured}; following the connector"
      )
    end
    advertised
  end

  # Published so the super admin screen can tell whether anyone is reading, and so the
  # fair share below knows how many of us there are.
  #
  # A draining process takes itself out of the registry at once rather than waiting for
  # the key to lapse: it is not going to read anything again, and a replacement that
  # counted it would claim half the shards and leave the rest unread for the whole
  # shutdown grace period.
  def heartbeat
    return redis.del(Consumer.consumer_key(consumer_id)) if @draining

    redis.set(Consumer.consumer_key(consumer_id), { 'shards' => workers.keys.sort, 'at' => Time.current.to_i }.to_json,
              ex: HEARTBEAT_TTL)
  end

  # How many shards this process may hold. Every consumer computes the same number from
  # the same registry, so the shards spread out without anyone coordinating.
  def fair_share
    [(shards.size.to_f / [peers, 1].max).ceil, 1].max
  end

  # SCAN rather than KEYS: this runs every tick in every consumer, against the Redis the
  # whole installation shares, and KEYS walks the entire keyspace under a lock.
  def peers
    pattern = Consumer.consumer_key('*')
    cursor = '0'
    count = 0
    loop do
      cursor, keys = redis.scan(cursor, match: pattern, count: SCAN_BATCH)
      count += keys.size
      break if cursor == '0'
    end
    count
  end

  def claim
    return if @draining

    share = fair_share
    shards.each do |shard|
      break if @threads.size >= share
      next if @threads.key?(shard)
      next unless redis.set(Consumer.lease_key(shard), consumer_id, nx: true, ex: LEASE_TTL)

      spawn_worker(shard)
    end
  end

  # A consumer that started alone holds every shard, and nothing would ever take one
  # back from it: the newcomers find every lease taken. Giving up the excess is what
  # makes a rolling restart converge instead of leaving one process reading everything.
  def rebalance
    return if @draining

    # Counted over the shards being read, not the leases still held: a worker that was
    # already told to stop is on its way out, and counting it again on the next tick
    # would stop another one, and another, until nothing was reading at all.
    excess = workers.size - fair_share
    return if excess <= 0

    workers.keys.sort.last(excess).each do |shard|
      Rails.logger.info("[WHATSAPP CONNECTOR] #{consumer_id} releasing shard #{shard} to a peer")
      stop_worker(shard)
    end
  end

  # Every shard whose thread is still around, not only the ones being read: a worker that
  # was told to stop is still inside its current entry, and its lease has to stay ours
  # until it is out.
  #
  # Losing a lease (a stall long enough for it to expire) means someone else may already
  # be reading the shard, so the worker is told to stop the moment it is noticed.
  def renew
    # A snapshot: stop_worker deletes from the table this is walking.
    held = @threads.keys
    held.each do |shard|
      next if redis.eval(RENEW_SCRIPT, keys: [Consumer.lease_key(shard)], argv: [consumer_id, LEASE_TTL]) == 1

      Rails.logger.warn("[WHATSAPP CONNECTOR] lost the lease on shard #{shard}")
      workers.delete(shard)&.stop
    end
  end

  # Threads that are out, either because they were told to stop and have finished, or
  # because they died on their own. This is the only place a lease is given back.
  def reap
    running = @threads.keys
    running.each do |shard|
      next if @threads[shard].alive?

      Rails.logger.warn("[WHATSAPP CONNECTOR] shard #{shard} worker stopped; releasing it") if workers.key?(shard)
      @threads.delete(shard)
      workers.delete(shard)
      release(shard)
    end
  end

  def spawn_worker(shard)
    worker = @worker_class.new(shard, consumer_id)
    workers[shard] = worker
    @threads[shard] = Thread.new { worker.run }
    Rails.logger.info("[WHATSAPP CONNECTOR] #{consumer_id} reading shard #{shard}")
  end

  # Tells the worker to stop and leaves it in @threads. `reap` is what releases the lease,
  # once the thread has actually exited: a shard handed over while its previous reader is
  # still inside a dispatch is a shard being read twice.
  def stop_worker(shard)
    workers.delete(shard)&.stop
  end

  def stop_all
    held = @threads.keys
    held.each { |shard| stop_worker(shard) }
    reap
  end

  # The last wait before the process goes. Whatever is still running after it keeps its
  # lease until that expires: a thread stuck inside one entry is worse to take a shard
  # away from than to leave the shard idle for LEASE_TTL.
  def drain
    held = @threads.keys
    # They were all told to stop together, so one deadline covers all of them.
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DRAIN_TIMEOUT
    held.each do |shard|
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @threads[shard]&.join(remaining) if remaining.positive?
    end
    reap
  end

  # Only the holder releases: a lease that already expired belongs to whoever took it.
  def release(shard)
    redis.eval(RELEASE_SCRIPT, keys: [Consumer.lease_key(shard)], argv: [consumer_id])
  end
end
