# Yields to the machine the backfill runs on.
#
# Two independent ceilings, because the two things a long backfill can exhaust are
# unrelated and want opposite responses. The provider meters bytes over a rolling day and
# answers an overdraft by locking IMAP for the whole account, which would take the live
# fetch down with it, so the budget *stops* the run and it resumes tomorrow. The host
# meters nothing and simply gets slower, which the agents feel as latency long before
# anything errors, so the load average only *pauses* it.
#
# The load is read from /proc, which inside a container is still the host's: that is the
# number the agents' latency tracks, not this process's share of it.
class Import::Email::Pacer
  # Checking every message would be a syscall per message for a number that moves on a
  # one-minute average; this is often enough to catch a spike within a few seconds of work.
  CHECK_EVERY = 25
  BACKOFF = 20.seconds

  attr_reader :bytes, :paused_for

  def initialize(budget_mb:, max_load:)
    @budget = budget_mb.to_f.megabytes
    @max_load = max_load.to_f
    @bytes = 0
    @seen = 0
    @paused_for = 0
  end

  def spend(count) = @bytes += count.to_i

  # Whether a transfer of this size still fits. Asked before a fetch, because
  # `over_budget?` can only ever be true of bytes already on the wire: a run that only
  # looks back overshoots the ceiling by whatever it just pulled down, and the ceiling is
  # there to sit under a provider limit whose answer to an overdraft is locking IMAP for
  # the account.
  def room_for?(count) = @bytes + count.to_i <= @budget
  def budget_mb_left = ((@budget - @bytes) / 1.megabyte).round
  def spent_mb = (@bytes / 1.megabyte.to_f).round(1)
  def over_budget? = @bytes >= @budget

  def load_average
    File.read('/proc/loadavg').split.first.to_f
  rescue StandardError
    0.0
  end

  # Blocks while the host is busy. Returns the seconds it waited, so the caller can report
  # a run that took six hours of which five were spent standing aside.
  def wait_for_room
    @seen += 1
    return 0 unless (@seen % CHECK_EVERY).zero?

    waited = 0
    while load_average > @max_load
      yield(load_average) if block_given?
      sleep BACKOFF
      waited += BACKOFF
      @paused_for += BACKOFF
    end
    waited
  end
end
