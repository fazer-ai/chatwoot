require 'rails_helper'

RSpec.describe Sidekiq::AurisKpisInjector do
  let(:html_body) { '<html><body><ul class="summary"><li>x</li></ul></body></html>' }
  let(:html_headers) { { 'Content-Type' => 'text/html' } }
  let(:app) { ->(_env) { [200, html_headers, [html_body]] } }
  let(:middleware) { described_class.new(app) }

  before do
    Sidekiq.redis do |conn|
      conn.keys('auris:sidekiq:*').each { |k| conn.del(k) }
    end
  end

  # Inside Sidekiq Web's Rack stack, PATH_INFO is relative to the
  # engine mount, so the dashboard arrives as `''` or `/`.
  def request(path: '/')
    middleware.call('PATH_INFO' => path)
  end

  it 'injects the Auris KPI row on the dashboard root' do
    _status, _headers, body = request

    expect(body.first).to include('Proc. hoje')
    expect(body.first).to include('Falhas hoje')
    expect(body.first).to include('KPI hoje')
    expect(body.first).to include('Proc. últ. hora')
    expect(body.first).to include('Falhas últ. hora')
    expect(body.first).to include('KPI últ. hora')
  end

  it 'reads day and minute counters from Redis to populate the row' do
    now = Time.now.utc
    Sidekiq.redis do |c|
      c.set(Sidekiq::AurisMetricsRecorder.day_key(Sidekiq::AurisMetricsRecorder::TYPE_PROCESSED, now.strftime('%Y%m%d')), 1500)
      c.set(Sidekiq::AurisMetricsRecorder.day_key(Sidekiq::AurisMetricsRecorder::TYPE_FAILED, now.strftime('%Y%m%d')), 30)
      c.set(Sidekiq::AurisMetricsRecorder.minute_key(Sidekiq::AurisMetricsRecorder::TYPE_PROCESSED, now.to_i / 60), 50)
      c.set(Sidekiq::AurisMetricsRecorder.minute_key(Sidekiq::AurisMetricsRecorder::TYPE_FAILED, now.to_i / 60), 5)
    end

    _status, _headers, body = request

    # 1500 with thousand-separator
    expect(body.first).to include('1.500')
    # KPI hoje = 100 - (30/1500*100) = 98,00%
    expect(body.first).to include('98,00%')
  end

  it 'reports 100% success when no jobs ran' do
    _status, _headers, body = request

    expect(body.first).to include('100,00%')
  end

  it 'leaves other Sidekiq paths untouched' do
    _status, _headers, body = request(path: '/queues')

    expect(body.first).to eq(html_body)
    expect(body.first).not_to include('Proc. hoje')
  end

  it 'also injects when PATH_INFO is empty (Rack normalises mount root that way too)' do
    _status, _headers, body = request(path: '')

    expect(body.first).to include('Proc. hoje')
  end

  it 'leaves non-HTML responses untouched' do
    json_app = ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{}']] }

    _status, _headers, body = described_class.new(json_app).call('PATH_INFO' => '/')

    expect(body.first).to eq('{}')
  end
end
