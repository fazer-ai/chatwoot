# Decides which event shards this process reads, and keeps a thread on each of them.
#
# Shards are claimed with a Redis lease, so several Chatwoot processes can run the
# consumer without ever reading the same shard twice. A process that dies stops
# renewing, its leases expire, and the survivors pick the shards up on their next tick.
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

  # Sidekiq's quiet phase: stop reading so a peer can take the shards over before this
  # process goes away.
  def quiet
    @stopped = true
    @mutex.synchronize { release_all }
  end

  def stop
    quiet
    @supervisor_thread&.join(TICK + 1)
    @supervisor_thread&.kill
    @mutex.synchronize do
      @threads.each_value { |thread| thread.join(5) }
      @threads.clear
      @workers.clear
    end
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

  def shards
    (0...Whatsapp::Connector.event_shards).to_a
  end

  # Published so the super admin screen can tell whether anyone is reading, and so the
  # fair share below knows how many of us there are.
  def heartbeat
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
    return if @stopped

    share = fair_share
    shards.each do |shard|
      break if workers.size >= share
      next if workers.key?(shard)
      next unless redis.set(Consumer.lease_key(shard), consumer_id, nx: true, ex: LEASE_TTL)

      spawn_worker(shard)
    end
  end

  # A consumer that started alone holds every shard, and nothing would ever take one
  # back from it: the newcomers find every lease taken. Giving up the excess is what
  # makes a rolling restart converge instead of leaving one process reading everything.
  def rebalance
    return if @stopped

    excess = workers.size - fair_share
    return if excess <= 0

    workers.keys.sort.last(excess).each do |shard|
      Rails.logger.info("[WHATSAPP CONNECTOR] #{consumer_id} releasing shard #{shard} to a peer")
      stop_worker(shard)
    end
  end

  # A lease is only worth renewing while this process still holds it: losing it (a stall
  # long enough for it to expire) means someone else may already be reading the shard,
  # so the worker has to go.
  def renew
    # A snapshot: stop_worker deletes from the table this is walking.
    held = workers.keys
    held.each do |shard|
      next if redis.eval(RENEW_SCRIPT, keys: [Consumer.lease_key(shard)], argv: [consumer_id, LEASE_TTL]) == 1

      Rails.logger.warn("[WHATSAPP CONNECTOR] lost the lease on shard #{shard}")
      stop_worker(shard)
    end
  end

  def reap
    running = @threads.keys
    running.each do |shard|
      next if @threads[shard].alive?

      Rails.logger.warn("[WHATSAPP CONNECTOR] shard #{shard} worker stopped; releasing it")
      stop_worker(shard)
    end
  end

  def spawn_worker(shard)
    worker = @worker_class.new(shard, consumer_id)
    workers[shard] = worker
    @threads[shard] = Thread.new { worker.run }
    Rails.logger.info("[WHATSAPP CONNECTOR] #{consumer_id} reading shard #{shard}")
  end

  def stop_worker(shard)
    workers.delete(shard)&.stop
    thread = @threads.delete(shard)
    thread&.join(2)
    release(shard)
  end

  def release_all
    held = workers.keys
    held.each { |shard| stop_worker(shard) }
  end

  # Only the holder releases: a lease that already expired belongs to whoever took it.
  def release(shard)
    redis.eval(RELEASE_SCRIPT, keys: [Consumer.lease_key(shard)], argv: [consumer_id])
  end
end
