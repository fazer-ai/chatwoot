# Server middleware that records processed/failed counts for the custom
# KPI row injected on the Sidekiq Web dashboard
# (see `Sidekiq::AurisKpisInjector`).
#
# Sidekiq's built-in stats give us TOTAL processed/failed (since the
# install was first deployed) and per-DAY history at day-granularity.
# That's too coarse for "what happened in the last hour", so this
# middleware maintains minute-granular counters in Redis under
# `auris:sidekiq:m:<processed|failed>:<unix_minute>` with a 90-minute
# TTL plus a day-granular counter under
# `auris:sidekiq:d:<processed|failed>:<YYYYMMDD>` with a 7-day TTL.
class Sidekiq::AurisMetricsRecorder
  TYPE_PROCESSED = 'processed'.freeze
  TYPE_FAILED = 'failed'.freeze

  MINUTE_TTL = 90 * 60  # 90 minutes — covers the rolling 60-min window plus margin
  DAY_TTL = 7 * 24 * 60 * 60

  def call(_worker, _job, _queue)
    yield
    record(TYPE_PROCESSED)
  rescue Exception # rubocop:disable Lint/RescueException
    record(TYPE_FAILED)
    raise
  end

  def self.minute_key(type, unix_minute)
    "auris:sidekiq:m:#{type}:#{unix_minute}"
  end

  def self.day_key(type, ymd)
    "auris:sidekiq:d:#{type}:#{ymd}"
  end

  private

  def record(type)
    now = Time.now.utc
    minute_key = self.class.minute_key(type, now.to_i / 60)
    day_key = self.class.day_key(type, now.strftime('%Y%m%d'))

    Sidekiq.redis do |conn|
      conn.pipelined do |pipeline|
        pipeline.incr(minute_key)
        pipeline.expire(minute_key, MINUTE_TTL)
        pipeline.incr(day_key)
        pipeline.expire(day_key, DAY_TTL)
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[AurisMetricsRecorder] failed to track #{type}: #{e.message}")
  end
end
