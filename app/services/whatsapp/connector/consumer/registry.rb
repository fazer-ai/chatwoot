# Who is reading the event streams right now.
#
# Every consumer publishes a short-lived key naming the shards it holds, and reads the
# others' to work out its own share. There is no coordinator: they all compute the same
# numbers from the same registry, so a process joining or leaving redistributes the
# shards without anyone being told.
class Whatsapp::Connector::Consumer::Registry
  Consumer = Whatsapp::Connector::Consumer

  # Short enough that a process which stopped announcing itself is out of the count in
  # seconds, long enough to survive one slow tick.
  TTL = 15
  # How many heartbeats one SCAN pass walks over. The registry is one key per process, so
  # a single pass covers any realistic deployment; the loop is there because SCAN
  # promises no more than a best effort per call.
  SCAN_BATCH = 100

  def initialize(redis, consumer_id)
    @redis = redis
    @consumer_id = consumer_id
  end

  def announce(shards)
    @redis.set(key(@consumer_id), { 'shards' => shards.sort, 'at' => Time.current.to_i }.to_json, ex: TTL)
  end

  # A process on its way out takes itself off at once rather than waiting for its key to
  # lapse: it is not going to read anything again, and a replacement that counted it
  # would claim a fraction of the shards and leave the rest unread for the grace period.
  def withdraw
    @redis.del(key(@consumer_id))
  end

  # How many shards each live consumer says it holds, this one included.
  #
  # SCAN rather than KEYS: this runs every tick in every consumer, against the Redis the
  # whole installation shares, and KEYS walks the entire keyspace under a lock.
  def held_counts
    keys.map { |member| Array(parse(member)['shards']).size }
  end

  private

  def keys
    cursor = '0'
    found = []
    loop do
      cursor, batch = @redis.scan(cursor, match: key('*'), count: SCAN_BATCH)
      found.concat(batch)
      break if cursor == '0'
    end
    found
  end

  # A heartbeat this build cannot read is still a consumer that is alive and holding
  # something, so it counts as a peer with nothing rather than not counting at all.
  def parse(member)
    JSON.parse(@redis.get(member).to_s)
  rescue JSON::ParserError
    {}
  end

  def key(consumer_id)
    Consumer.consumer_key(consumer_id)
  end
end
