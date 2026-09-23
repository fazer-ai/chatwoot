# How many history import batches may run at once across the whole instance, whatever the
# number of Sidekiq processes and threads.
#
# One pairing fans its dump out as a job per chat per frame, and with nothing holding them
# back 154 ran at once on a production instance: every host saturated and the web process
# answered 503 to live webhooks. Queue priority did not help, because once the imports held
# the threads and the CPU, a live job first in line still waited for the processor.
#
# It sits beside the chat lock (see Locks) and is taken before it: a batch whose chat is busy
# gives its slot back on the way out instead of holding the cap while it waits.
module Whatsapp::Session::Inbound::ImportSlots
  # Raised when every slot is taken. The job files itself for later rather than retrying, so
  # waiting for a slot spends no retry budget.
  class Full < StandardError; end

  DEFAULT_CONCURRENCY = 4
  KEY = 'WHATSAPP::HISTORY_IMPORT_SLOTS'.freeze
  # A slot is a lease rather than a counter, because a worker killed mid-import never runs
  # its `ensure`: a counter would keep that slot forever, and a few kills would end history
  # import on the instance. The lease is the chat lock's, which is already how long a batch
  # is allowed to run.
  LEASE = Whatsapp::Session::Inbound::Locks::IMPORT_CHAT_LOCK_TTL
  # Taking a slot is a read and a write that must see the same set. Under contention the
  # optimistic transaction loses to another worker; losing a few times in a row is read as
  # no slot, and the job simply comes back later.
  ATTEMPTS = 5

  module_function

  def with_slot(limit: concurrency)
    token = claim(limit)
    raise Full, "all #{limit} history import slots are taken" unless token

    begin
      yield
    ensure
      Redis::Alfred.with { |conn| conn.zrem(KEY, token) }
    end
  end

  # A positive whole number, or the default. Zero, a negative or a garbled value would
  # otherwise park every batch forever in silence, which is worse than the default cap.
  def concurrency
    value = Integer(ENV.fetch('HISTORY_IMPORT_MAX_CONCURRENCY', ''), exception: false)
    value&.positive? ? value : DEFAULT_CONCURRENCY
  end

  def taken
    Redis::Alfred.with { |conn| conn.zcount(KEY, Time.now.to_f, '+inf') }
  end

  # The slots are a sorted set of lease tokens scored by expiry, so a lease its holder never
  # gave back stops counting on its own. WATCH makes the count and the add one decision: a
  # worker that took a slot in between aborts this transaction instead of both taking the
  # last one.
  def claim(limit)
    token = SecureRandom.uuid
    ATTEMPTS.times do
      outcome = Redis::Alfred.with do |conn|
        conn.watch(KEY) do
          now = Time.now.to_f
          next conn.unwatch && :full if conn.zcount(KEY, now, '+inf') >= limit

          conn.multi do |transaction|
            transaction.zremrangebyscore(KEY, '-inf', now)
            transaction.zadd(KEY, now + LEASE.to_i, token)
            transaction.expire(KEY, LEASE.to_i)
          end
        end
      end
      return nil if outcome == :full
      return token if outcome
    end
    nil
  end
end
