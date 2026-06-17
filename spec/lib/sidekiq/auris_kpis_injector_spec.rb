require 'rails_helper'

RSpec.describe Sidekiq::AurisKpisInjector do
  # Matches the structure Sidekiq's `_summary.erb` actually renders —
  # also includes a navbar `<ul>` BEFORE the summary so the spec proves
  # we don't accidentally insert after the first `</ul>` we find.
  let(:html_body) do
    <<~HTML
      <html>
        <body>
          <nav><ul class="nav navbar-nav"><li>tab</li></ul></nav>
          <div class="summary_bar">
            <ul class="list-unstyled summary row">
              <li class="processed col-sm-1"><span class="count" data-nwp>10</span><span class="desc">Processed</span></li>
              <li class="dead col-sm-1"><a href="/morgue"><span class="count" data-nwp>1</span><span class="desc">Dead</span></a></li>
            </ul>
          </div>
          <main>page body</main>
        </body>
      </html>
    HTML
  end
  let(:html_headers) { { 'Content-Type' => 'text/html' } }
  let(:app) { ->(_env) { [200, html_headers, [html_body]] } }
  let(:middleware) { described_class.new(app) }

  before do
    Sidekiq.redis do |conn|
      conn.keys('auris:sidekiq:*').each { |k| conn.del(k) }
    end
  end

  it 'injects the Auris KPI row right after Sidekiq summary block' do
    _status, _headers, body = middleware.call({})

    html = body.first
    expect(html).to include('Proc. hoje')
    expect(html).to include('Falhas hoje')
    expect(html).to include('KPI hoje')
    expect(html).to include('Proc. últ. hora')
    expect(html).to include('Falhas últ. hora')
    expect(html).to include('KPI últ. hora')

    # Make sure we inserted AFTER the summary, not after the navbar.
    summary_end = html.index('</ul>', html.index('list-unstyled summary'))
    auris_start = html.index('Proc. hoje')
    expect(auris_start).to be > summary_end
  end

  it 'reads day and minute counters from Redis to populate the row' do
    now = Time.now.utc
    Sidekiq.redis do |c|
      c.set(Sidekiq::AurisMetricsRecorder.day_key(Sidekiq::AurisMetricsRecorder::TYPE_PROCESSED, now.strftime('%Y%m%d')), 1500)
      c.set(Sidekiq::AurisMetricsRecorder.day_key(Sidekiq::AurisMetricsRecorder::TYPE_FAILED, now.strftime('%Y%m%d')), 30)
      c.set(Sidekiq::AurisMetricsRecorder.minute_key(Sidekiq::AurisMetricsRecorder::TYPE_PROCESSED, now.to_i / 60), 50)
      c.set(Sidekiq::AurisMetricsRecorder.minute_key(Sidekiq::AurisMetricsRecorder::TYPE_FAILED, now.to_i / 60), 5)
    end

    _status, _headers, body = middleware.call({})

    expect(body.first).to include('1.500')
    # KPI hoje = 100 - (30/1500*100) = 98,00%
    expect(body.first).to include('98,00%')
  end

  it 'reports 100% success when no jobs ran' do
    _status, _headers, body = middleware.call({})

    expect(body.first).to include('100,00%')
  end

  it 'leaves HTML without the summary block untouched (e.g. login screen)' do
    app = ->(_env) { [200, html_headers, ['<html><body>Login</body></html>']] }

    _status, _headers, body = described_class.new(app).call({})

    expect(body.first).to eq('<html><body>Login</body></html>')
  end

  it 'leaves non-HTML responses untouched (poll JSON endpoints)' do
    json_app = ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{}']] }

    _status, _headers, body = described_class.new(json_app).call({})

    expect(body.first).to eq('{}')
  end
end
