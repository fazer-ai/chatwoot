# Which event streams this consumer should be reading right now.
#
# The count comes from the running connector, and is then fixed for the life of this
# process. It has to be: the connector re-maps sessions across the streams when it
# changes, so a session's older events sit on the stream it used to hash to while its
# newer ones arrive on the one it hashes to now, and whichever worker gets ahead pushes
# the session cursor past what the other has not reached yet.
#
# There is no way to follow that safely while running. Waiting for the old mapping to
# finish only works when the streams it used stop being written to, and they generally
# do not: 2 to 4 leaves the old events on 0 and 1, which keep receiving new ones, and
# even 8 to 6 moves sessions between streams that both survive. Changing the count is a
# planned operation, so this reads the mapping it started with and says loudly when the
# connector has moved on.
#
# What is still followed is the tail of a previous topology: streams above the current
# range that a restart inherited. Those really have stopped being written to, so they
# drain, and while they still hold work they are all this consumer reads, in case a
# session moved off them.
class Whatsapp::Connector::Consumer::ShardMap
  Consumer = Whatsapp::Connector::Consumer

  SCAN_BATCH = 100

  def initialize(redis)
    @redis = redis
  end

  def shards
    count = mapping_size
    retired = retired_with_work(count)
    return (0...count).to_a if retired.empty?

    Rails.logger.warn("[WHATSAPP CONNECTOR] draining retired shards #{retired.join(', ')} before reading the rest")
    retired
  end

  private

  def mapping_size
    advertised = Whatsapp::Connector.advertised_shards(@redis)
    @mapping_size ||= advertised
    refuse_hot_change(advertised) unless advertised == @mapping_size
    @mapping_size
  end

  # Loud, because it needs a person: the connector has to stop, the consumers have to
  # finish what is on the streams, and then everything restarts on the new count.
  # Following it here instead would quietly reorder the sessions that moved.
  def refuse_hot_change(advertised)
    Rails.logger.error(
      "[WHATSAPP CONNECTOR] the connector now publishes #{advertised} event shards and this consumer is reading " \
      "#{@mapping_size}. Re-sharding while running would reorder the sessions that moved, so it keeps the mapping " \
      'it started with: stop the connector, let the consumers drain, and restart them on the new count.'
    )
  end

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
