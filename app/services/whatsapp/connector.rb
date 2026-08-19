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

  # How many event streams the connector fans sessions across. Both sides must agree,
  # which is why the connector publishes its own value in `wa:meta` and refuses to start
  # when they differ.
  def self.event_shards
    ENV.fetch('WHATSAPP_CONNECTOR_EVENT_SHARDS', '8').to_i
  end
end
