# The transport to the Go connector (the `native` provider).
#
# Chatwoot and the connector share the Redis that is already on the machine: commands
# go on a per-session stream, events come back on sharded streams, and RPC answers on a
# short-lived list. Nothing about this is namespaced by Redis::Namespace: the keys are
# read and written by another process, so they are plain, prefixed keys.
module Whatsapp::Connector
  # Kept configurable on both sides for the rare deployment that shares one Redis
  # between two Chatwoot installations.
  def self.prefix
    ENV.fetch('WHATSAPP_CONNECTOR_REDIS_PREFIX', 'wa:')
  end

  def self.key(*parts)
    "#{prefix}#{parts.join(':')}"
  end

  def self.enabled?
    ENV.fetch('WHATSAPP_CONNECTOR_ENABLED', 'false') == 'true'
  end

  # How many event streams the connector fans sessions across, as this installation is
  # configured. Only the answer until a connector has run: it publishes the count it is
  # actually using, and that one wins.
  def self.event_shards
    ENV.fetch('WHATSAPP_CONNECTOR_EVENT_SHARDS', '8').to_i
  end

  # The count the running connector publishes, which is what decides where a session's
  # events land. Reading fewer than it publishes would leave whole streams unconsumed and
  # the inboxes sharded onto them silently deaf.
  def self.advertised_shards(redis)
    configured = event_shards
    advertised = redis.hget(key('meta'), 'event_shards').to_i
    return configured unless advertised.positive?

    warn_on_shard_drift(advertised, configured) unless advertised == configured
    advertised
  end

  # Following the connector is right either way. Above the configured number it also
  # means the database pool, sized from that number, has no connections reserved for the
  # extra threads.
  def self.warn_on_shard_drift(advertised, configured)
    room = advertised > configured ? ', raise WHATSAPP_CONNECTOR_EVENT_SHARDS to match so the database pool has room' : ''
    Rails.logger.warn(
      "[WHATSAPP CONNECTOR] the connector publishes #{advertised} event shards, this is configured for " \
      "#{configured}; following the connector#{room}"
    )
  end
end
