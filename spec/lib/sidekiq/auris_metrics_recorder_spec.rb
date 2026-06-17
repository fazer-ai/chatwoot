require 'rails_helper'

RSpec.describe Sidekiq::AurisMetricsRecorder do
  let(:middleware) { described_class.new }

  before do
    Sidekiq.redis do |conn|
      conn.keys('auris:sidekiq:*').each { |k| conn.del(k) }
    end
  end

  it 'increments today and current-minute processed counters when the job succeeds' do
    middleware.call(nil, nil, 'default') { :ok }

    now = Time.now.utc
    day = Sidekiq.redis { |c| c.get(described_class.day_key(described_class::TYPE_PROCESSED, now.strftime('%Y%m%d'))) }
    minute = Sidekiq.redis { |c| c.get(described_class.minute_key(described_class::TYPE_PROCESSED, now.to_i / 60)) }

    expect(day).to eq('1')
    expect(minute).to eq('1')
  end

  it 'increments failed counters and re-raises when the job raises' do
    expect do
      middleware.call(nil, nil, 'default') { raise 'boom' }
    end.to raise_error('boom')

    now = Time.now.utc
    day = Sidekiq.redis { |c| c.get(described_class.day_key(described_class::TYPE_FAILED, now.strftime('%Y%m%d'))) }

    expect(day).to eq('1')
  end

  it 'sets TTL on the counters so old buckets disappear automatically' do
    middleware.call(nil, nil, 'default') { :ok }

    now = Time.now.utc
    minute_ttl = Sidekiq.redis { |c| c.ttl(described_class.minute_key(described_class::TYPE_PROCESSED, now.to_i / 60)) }
    day_ttl = Sidekiq.redis { |c| c.ttl(described_class.day_key(described_class::TYPE_PROCESSED, now.strftime('%Y%m%d'))) }

    expect(minute_ttl).to be_between(1, described_class::MINUTE_TTL)
    expect(day_ttl).to be_between(1, described_class::DAY_TTL)
  end
end
