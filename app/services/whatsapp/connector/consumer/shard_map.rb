# Which event streams this consumer should be reading right now.
#
# Normally that is simply the range the running connector publishes. It stops being
# simple when that count changes: the connector re-maps sessions across the streams, so
# a session's older events sit on the stream it used to hash to while its newer ones
# arrive on the one it hashes to now.
#
# Reading both at once would hand one session's events to two workers, and the newer one
# would push the session cursor past events the older one has not reached yet, which the
# cursor then discards. Ordering is the one thing this design cannot trade, so the
# answer here is a phase: while anything the connector has stopped writing to still has
# work on it, that is all this consumer reads, and the new range waits. The pause is
# bounded, because a retired stream is not being written to any more.
class Whatsapp::Connector::Consumer::ShardMap
  Consumer = Whatsapp::Connector::Consumer

  SCAN_BATCH = 100

  def initialize(redis)
    @redis = redis
  end

  def shards
    advertised = Whatsapp::Connector.advertised_shards(@redis)
    retired = retired_with_work(advertised)
    return (0...advertised).to_a if retired.empty?

    Rails.logger.warn("[WHATSAPP CONNECTOR] draining retired shards #{retired.join(', ')} before reading the rest")
    retired
  end

  private

  def retired_with_work(advertised)
    existing.select { |shard| shard >= advertised && backlog?(shard) }.sort
  end

  # From the keys that are there, not from the local setting: the connector may have been
  # publishing more shards than this installation was ever configured for, and those
  # streams have to be found too. The lease keys share the prefix, so only the ones
  # ending in the shard number count.
  def existing
    cursor = '0'
    found = []
    loop do
      cursor, keys = @redis.scan(cursor, match: Consumer.shard_key('*'), count: SCAN_BATCH)
      found.concat(keys)
      break if cursor == '0'
    end
    found.filter_map { |key| key[/:(\d+)\z/, 1]&.to_i }
  end

  # Pending entries, or entries the group has never been handed. Asked this way rather
  # than through the group's lag, which Redis only reports from 7 on.
  def backlog?(shard)
    stream = Consumer.shard_key(shard)
    group = @redis.xinfo(:groups, stream).find { |entry| entry['name'] == Consumer::GROUP }
    # The connector can have written to a stream before any consumer created the group.
    # Answering "nothing here" would mean nobody ever creates it, and those events would
    # sit on the stream for good.
    return @redis.xlen(stream).positive? if group.nil?
    return true if group['pending'].to_i.positive?

    group['last-delivered-id'] != @redis.xinfo(:stream, stream)['last-generated-id']
  rescue Redis::CommandError
    # No such key: a stream that was never written to has nothing to drain.
    false
  end
end
