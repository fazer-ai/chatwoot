# Rack middleware that injects an extra "Auris" summary row right
# below Sidekiq Web's default `processados / falhas / ocupados / ...`
# block on the dashboard. Numbers come from the per-minute and per-day
# counters maintained by `Sidekiq::AurisMetricsRecorder`.
#
# Two windows are shown:
#   - Hoje                  (sum of today's day-counter)
#   - Últimos 60 min         (sum of the last 60 minute-counters)
#
# Each window exposes Proc., Falhas and a "KPI" success-rate metric
# computed as `100% - (failed / processed)`.
class Sidekiq::AurisKpisInjector
  ANCHOR = '</ul>'.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    return [status, headers, body] unless inject?(env, headers)

    html = collect(body)
    extra = render_row
    html = html.sub(ANCHOR, "#{ANCHOR}\n#{extra}")

    new_headers = headers.dup
    new_headers['Content-Length'] = html.bytesize.to_s if new_headers.key?('Content-Length') || new_headers.key?('content-length')

    [status, new_headers, [html]]
  end

  private

  # Sidekiq's dashboard is the ROOT of the mount point. Rack strips the
  # mount prefix into SCRIPT_NAME and leaves PATH_INFO as `''` or `/`,
  # regardless of where the engine was mounted — `/monitoring/sidekiq`
  # in this project, but the middleware shouldn't assume that path.
  def inject?(env, headers)
    path = env['PATH_INFO'].to_s
    return false unless path.empty? || path == '/'

    content_type = headers['Content-Type'] || headers['content-type']
    content_type&.include?('text/html')
  end

  def collect(body)
    chunks = body.map { |chunk| chunk }
    body.close if body.respond_to?(:close)
    chunks.join
  end

  def render_row
    m = fetch_metrics
    items = [
      ['processed', m[:today_processed],                                              'Proc. hoje'],
      ['failed',    m[:today_failed],                                                 'Falhas hoje'],
      ['processed', success_rate(m[:today_processed], m[:today_failed]),              'KPI hoje'],
      ['processed', m[:hour_processed],                                               'Proc. últ. hora'],
      ['failed',    m[:hour_failed],                                                  'Falhas últ. hora'],
      ['processed', success_rate(m[:hour_processed], m[:hour_failed]),                'KPI últ. hora']
    ]
    lis = items.map { |klass, value, label| li_for(klass, value, label) }.join("\n")
    <<~HTML
      <ul class="list-unstyled summary row" style="margin-top: 8px; border-top: 1px solid #eee; padding-top: 8px;">
        #{lis}
      </ul>
    HTML
  end

  def li_for(klass, value, label)
    value_str = value.is_a?(Numeric) ? number_with_delimiter(value) : value
    <<~LI
      <li class="#{klass} col-sm-2">
        <span class="count" data-nwp>#{value_str}</span>
        <span class="desc">#{label}</span>
      </li>
    LI
  end

  def fetch_metrics
    now = Time.now.utc
    today_proc, today_fail, hour_proc, hour_fail = read_counters(now)

    {
      today_processed: today_proc.to_i,
      today_failed: today_fail.to_i,
      hour_processed: hour_proc.compact.sum(&:to_i),
      hour_failed: hour_fail.compact.sum(&:to_i)
    }
  rescue StandardError => e
    Rails.logger.warn("[AurisKpisInjector] failed to fetch metrics: #{e.message}")
    { today_processed: 0, today_failed: 0, hour_processed: 0, hour_failed: 0 }
  end

  def read_counters(now)
    ymd = now.strftime('%Y%m%d')
    current_minute = now.to_i / 60
    minute_keys = lambda do |type|
      (0...60).map { |i| Sidekiq::AurisMetricsRecorder.minute_key(type, current_minute - i) }
    end

    Sidekiq.redis do |conn|
      conn.pipelined do |p|
        p.get(Sidekiq::AurisMetricsRecorder.day_key(Sidekiq::AurisMetricsRecorder::TYPE_PROCESSED, ymd))
        p.get(Sidekiq::AurisMetricsRecorder.day_key(Sidekiq::AurisMetricsRecorder::TYPE_FAILED, ymd))
        p.mget(*minute_keys.call(Sidekiq::AurisMetricsRecorder::TYPE_PROCESSED))
        p.mget(*minute_keys.call(Sidekiq::AurisMetricsRecorder::TYPE_FAILED))
      end
    end
  end

  # Success-rate formula requested by the operator:
  # `100% - (failed / processed)`. Treats zero processed as 100%
  # (no jobs ran → no failures to count).
  def success_rate(processed, failed)
    return '100,00%' if processed.zero?

    pct = 100.0 - (failed.to_f / processed * 100)
    "#{format('%.2f', pct).tr('.', ',')}%"
  end

  def number_with_delimiter(number)
    number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse
  end
end
