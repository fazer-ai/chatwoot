require Rails.root.join('lib/redis/config')

schedule_file = 'config/schedule.yml'

# Customise the Sidekiq Web UI mounted at `/monitoring/sidekiq` (see
# `config/routes.rb`).
#
# - `PriorityColumnInjector`: injects a `<script>` tag that adds a
#   "Prioridade" column to the /queues page, served from
#   `public/sidekiq-priority-column.js`. Wired at the Rack layer because
#   Sidekiq 7.3 removed `Sidekiq::Web.custom_javascript=`.
# - `AurisKpisInjector`: injects an extra summary row on the dashboard
#   with daily and last-hour Processed / Failed / Success-rate KPIs,
#   sourced from counters maintained by `AurisMetricsRecorder` (server
#   middleware below).
require 'sidekiq/web'
require Rails.root.join('lib/sidekiq/priority_column_injector')
require Rails.root.join('lib/sidekiq/auris_kpis_injector')
Sidekiq::Web.use Sidekiq::PriorityColumnInjector
Sidekiq::Web.use Sidekiq::AurisKpisInjector

require Rails.root.join('lib/sidekiq/auris_metrics_recorder')

Sidekiq.configure_client do |config|
  config.redis = Redis::Config.app
end

# Logs whenever a job is pulled off Redis for execution.
class ChatwootDequeuedLogger
  def call(_worker, job, queue)
    payload = job['args'].first
    Sidekiq.logger.info("Dequeued #{job['wrapped']} #{payload['job_id']} from #{queue}")
    yield
  end
end

Sidekiq.configure_server do |config|
  config.redis = Redis::Config.app

  config.server_middleware do |chain|
    chain.add Sidekiq::AurisMetricsRecorder
  end

  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_SIDEKIQ_DEQUEUE_LOGGER', false))
    config.server_middleware do |chain|
      chain.add ChatwootDequeuedLogger
    end
  end

  # skip the default start stop logging
  if Rails.env.production?
    config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    config[:skip_default_job_logging] = true
    config.logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'info').upcase.to_s)
  end
end

# https://github.com/ondrejbartas/sidekiq-cron
# Reduce poll interval for second-precision cron jobs
Sidekiq::Options[:cron_poll_interval] = 10

Rails.application.reloader.to_prepare do
  # load_from_hash! upserts jobs from the YAML and removes any Redis-persisted
  # jobs that share the same source tag but are no longer in the file.
  # This ensures deleted schedule entries are cleaned up on deploy.
  #
  # Runs on EVERY Rails process boot (web, sidekiq server, console, rake) —
  # not only on `Sidekiq.server?`. Rolling deploys often restart web
  # containers while the sidekiq container survives untouched; a
  # server-only guard means new cron entries added to schedule.yml stay
  # missing from Redis until the sidekiq container itself restarts. Real
  # incident: the `super_admin_health_score_daily_snapshot_job` cron was
  # added in commit 6248fb2ee (25/05/2026), ran once the next day, and
  # then silently sat unregistered for ~2.5 months because deploys never
  # bounced the sidekiq container. Loading from any process is safe:
  # Redis is shared, the operation is idempotent, and only sidekiq server
  # actually executes the crons.
  if File.exist?(schedule_file)
    schedule = YAML.load_file(schedule_file)

    # Cron entries removed from schedule.yml but possibly still in Redis
    # with source:'dynamic' (predating the source tag). load_from_hash!
    # only cleans up source:'schedule' entries, so these need explicit removal.
    # Remove names from this list once they've been through a deploy cycle.
    %w[bulk_auto_assignment_job].each { |name| Sidekiq::Cron::Job.destroy(name) }

    Sidekiq::Cron::Job.load_from_hash!(schedule, source: 'schedule')
  end
end
