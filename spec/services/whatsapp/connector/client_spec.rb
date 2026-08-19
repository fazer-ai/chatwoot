require 'rails_helper'

# These run against a real Redis: MockRedis (which the app's own pools use in tests)
# implements none of the stream or blocking commands this depends on.
RSpec.describe Whatsapp::Connector::Client, :redis_streams do
  subject(:client) { described_class.new(session_id) }

  let(:session_id) { '9f1c0f4e-6a2b-4c8e-9d1a-2b3c4d5e6f70' }
  let(:prefix) { "watest#{SecureRandom.hex(4)}:" }
  let(:model) { Whatsapp::Session::Model }
  let(:redis) { Redis.new(Redis::Config.app) }
  let(:command) { model::Commands::SessionStatus.new }

  around do |example|
    with_modified_env(WHATSAPP_CONNECTOR_REDIS_PREFIX: prefix) { example.run }
    keys = redis.keys("#{prefix}*")
    redis.del(*keys) if keys.any?
  end

  def frame_of(entry)
    entry.last.transform_values { |value| value.start_with?('{') ? JSON.parse(value) : value }
  end

  describe '#publish' do
    it 'queues the command on the stream of its session' do
      id = client.publish(model::Commands::SessionDisconnect.new)

      entries = redis.xrange("#{prefix}cmd:#{session_id}")
      expect(entries.size).to eq(1)
      frame = frame_of(entries.first)
      expect(frame).to include('v' => '1', 'type' => 'session.disconnect', 'sid' => session_id, 'id' => id)
      # Fire and forget: nothing is waiting for an answer.
      expect(frame).not_to have_key('reply_to')
    end
  end

  describe '#call' do
    before { redis.hset("#{prefix}instance:one", 'protocol_min', '1', 'protocol_max', '1') && redis.sadd("#{prefix}instances", 'one') }

    it 'sends the command with a deadline and returns what the connector answered' do
      allow(SecureRandom).to receive(:uuid).and_return('cmd-0001')
      redis.lpush("#{prefix}reply:cmd-0001", { 'v' => 1, 'id' => 'cmd-0001', 'ok' => true,
                                               'result' => { 'connection' => 'open' } }.to_json)

      expect(client.call(command)).to eq({ 'connection' => 'open' })

      frame = frame_of(redis.xrange("#{prefix}cmd:#{session_id}").first)
      expect(frame['reply_to']).to eq("#{prefix}reply:cmd-0001")
      expect(frame['deadline'].to_i).to be > frame['ts'].to_i
    end

    it 'raises the error the connector reported, mapped to its class' do
      allow(SecureRandom).to receive(:uuid).and_return('cmd-0002')
      redis.lpush("#{prefix}reply:cmd-0002", { 'v' => 1, 'id' => 'cmd-0002', 'ok' => false,
                                               'error' => { 'code' => 'not_connected', 'message' => 'session is closed' } }.to_json)

      expect { client.call(command) }.to raise_error(Whatsapp::Session::Errors::NotConnected, /session is closed/)
    end

    it 'gives up when nobody answers' do
      expect { client.call(command, timeout: 1) }.to raise_error(Whatsapp::Session::Errors::Timeout)
    end

    it 'refuses to queue anything while no connector is running' do
      redis.del("#{prefix}instances")

      expect { client.call(command) }.to raise_error(Whatsapp::Session::Errors::ProviderUnavailable, /no whatsapp connector is running/)
      expect(redis.exists?("#{prefix}cmd:#{session_id}")).to be(false)
    end

    it 'refuses to queue a frame the running connector has moved past' do
      redis.hset("#{prefix}instance:one", 'protocol_min', '2', 'protocol_max', '3')

      expect { client.call(command) }.to raise_error(Whatsapp::Session::Errors::ProviderUnavailable, /speaks protocol 1/)
      expect(redis.exists?("#{prefix}cmd:#{session_id}")).to be(false)
    end
  end

  # Raw, a checkout timeout reaches the send path as a 500: everything above this layer
  # rescues Whatsapp::Session::Errors, and a connection it could not get means the same
  # to them as a connector it could not reach.
  it 'answers a pool that has nothing free in the layer own errors' do
    allow(described_class).to receive(:pool).and_raise(ConnectionPool::TimeoutError, 'waited 5 seconds')

    expect { client.publish(model::Commands::SessionDisconnect.new) }
      .to raise_error(Whatsapp::Session::Errors::ProviderUnavailable, /no connector connection available/)
  end

  # Everything above this layer rescues Whatsapp::Session::Errors and nothing else, and
  # the jobs that retry do it on ProviderUnavailable, so a Redis outage that arrived raw
  # reached a group controller or a send as a 500 and skipped the retry meant for it.
  it 'answers a Redis that is not there in the layer own errors' do
    allow_any_instance_of(Redis).to receive(:xadd).and_raise(Redis::CannotConnectError, 'connection refused') # rubocop:disable RSpec/AnyInstance

    expect { client.publish(model::Commands::SessionDisconnect.new) }
      .to raise_error(Whatsapp::Session::Errors::ProviderUnavailable, /transport failed/)
  end

  describe 'the instance registry' do
    it 'reports nobody home when no instance is registered' do
      expect(client).not_to be_available
      expect(client).not_to be_compatible
    end

    it 'is compatible when the protocol ranges overlap' do
      redis.hset("#{prefix}instance:one", 'protocol_min', '1', 'protocol_max', '2', 'media_token', 'secret')
      redis.sadd("#{prefix}instances", 'one')

      expect(client).to be_available
      expect(client).to be_compatible
    end

    # A blob lives on the instance that downloaded it, and each instance only accepts the
    # token it published, so picking whichever the registry listed first got a 401 on
    # every blob that happened to belong to another one.
    it 'answers with the media token of the instance serving the URL' do
      redis.hset("#{prefix}instance:one", 'advertise_url', 'http://wa-1:8080', 'media_token', 'token-one')
      redis.hset("#{prefix}instance:two", 'advertise_url', 'http://wa-2:8080', 'media_token', 'token-two')
      redis.sadd("#{prefix}instances", %w[one two])

      expect(client.media_token('http://wa-2:8080/media/abc')).to eq('token-two')
      expect(client.media_token('http://wa-1:8080/media/abc')).to eq('token-one')
    end

    it 'falls back to a published token for a URL no instance advertises' do
      redis.hset("#{prefix}instance:one", 'advertise_url', 'http://wa-1:8080', 'media_token', 'token-one')
      redis.sadd("#{prefix}instances", 'one')

      expect(client.media_token('https://cdn.example.test/media/abc')).to eq('token-one')
    end

    it 'is incompatible when the connector moved past this protocol' do
      redis.hset("#{prefix}instance:one", 'protocol_min', '2', 'protocol_max', '3')
      redis.sadd("#{prefix}instances", 'one')

      expect(client).to be_available
      expect(client).not_to be_compatible
    end
  end
end
