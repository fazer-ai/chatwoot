# The lock that makes a shard single-reader. One consumer holds a shard's lease, reads
# it, and keeps the lease alive for as long as its worker is around; a process that dies
# stops renewing and the lease lapses, which is how its shards move to the survivors.
#
# Taking is a plain SET NX, but extending and giving back both compare the holder and act
# in the same round trip. Read-then-write would let the lease change hands in between,
# and this process would then extend a lease another consumer is already reading under,
# or delete one a third has since taken.
class Whatsapp::Connector::Consumer::ShardLease
  Consumer = Whatsapp::Connector::Consumer

  # Long enough to survive a slow tick, short enough that a crashed process's shards
  # move within seconds.
  TTL = 30

  RENEW = <<~LUA.freeze
    if redis.call('get', KEYS[1]) == ARGV[1] then
      return redis.call('expire', KEYS[1], ARGV[2])
    end
    return 0
  LUA

  RELEASE = <<~LUA.freeze
    if redis.call('get', KEYS[1]) == ARGV[1] then
      return redis.call('del', KEYS[1])
    end
    return 0
  LUA

  def initialize(redis, consumer_id)
    @redis = redis
    @consumer_id = consumer_id
  end

  def take(shard)
    @redis.set(key(shard), @consumer_id, nx: true, ex: TTL).present?
  end

  # False when the lease is no longer ours, which is the caller's signal to stop reading
  # the shard: somebody else may already have it.
  def renew(shard)
    @redis.eval(RENEW, keys: [key(shard)], argv: [@consumer_id, TTL]) == 1
  end

  def release(shard)
    @redis.eval(RELEASE, keys: [key(shard)], argv: [@consumer_id])
  end

  private

  def key(shard)
    Consumer.lease_key(shard)
  end
end
