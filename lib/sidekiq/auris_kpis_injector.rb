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
  # Matches Sidekiq's `_summary.erb` block as a whole. Anchoring on the
  # `</ul>` alone would inject after the FIRST `</ul>` (which is the
  # navbar), and the row would be rendered outside the CSS scope that
  # styles the summary numbers as stacked count+desc cards.
  SUMMARY_BLOCK = %r{<ul class="list-unstyled summary row">.*?</ul>}m

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    return [status, headers, body] unless inject?(headers)

    html = collect(body)
    return [status, headers, [html]] unless SUMMARY_BLOCK.match?(html)

    extra = render_row
    html = html.sub(SUMMARY_BLOCK) { |match| "#{match}\n#{extra}" }

    new_headers = headers.dup
    new_headers['Content-Length'] = html.bytesize.to_s if new_headers.key?('Content-Length') || new_headers.key?('content-length')

    [status, new_headers, [html]]
  end

  private

  # The summary is rendered by `layout.erb`, so every Sidekiq Web HTML
  # page carries the bar. No PATH_INFO filter — we just skip non-HTML
  # responses (poll JSON endpoints).
  def inject?(headers)
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
      ['processed', m[:today_processed],                                'Proc. hoje'],
      ['failed',    m[:today_failed],                                   'Falhas hoje'],
      ['processed', success_rate(m[:today_processed], m[:today_failed]), 'KPI hoje'],
      ['processed', m[:hour_processed],                                 'Proc. últ. hora'],
      ['failed',    m[:hour_failed],                                    'Falhas últ. hora'],
      ['processed', success_rate(m[:hour_processed], m[:hour_failed]),  'KPI últ. hora']
    ]
    lis = items.map { |klass, value, label| li_for(klass, value, label) }.join("\n")
    %(<ul class="list-unstyled summary row">\n#{lis}\n</ul>)
  end

  def li_for(klass, value, label)
    value_str = value.is_a?(Numeric) ? number_with_delimiter(value) : value
    <<~LI
      <li class="#{klass} col-sm-1">
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
