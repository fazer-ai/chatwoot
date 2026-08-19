require 'rails_helper'

RSpec.describe Whatsapp::Connector::Consumer::Supervisor, :redis_streams do
  subject(:supervisor) { described_class.new(consumer_id: 'consumer-1', worker_class: worker_class) }

  let(:prefix) { "watest#{SecureRandom.hex(4)}:" }
  let(:redis) { Redis.new(Redis::Config.app) }
  # A worker that only reports whether it is alive: the claim loop is what is under test.
  let(:worker_class) do
    Class.new do
      attr_reader :shard

      def initialize(shard, _consumer_id)
        @shard = shard
        @queue = Queue.new
      end

      def run = @queue.pop
      def stop = @queue << :stop
    end
  end

  around do |example|
    with_modified_env(WHATSAPP_CONNECTOR_REDIS_PREFIX: prefix, WHATSAPP_CONNECTOR_EVENT_SHARDS: '4') { example.run }
    supervisor.stop
    keys = redis.keys("#{prefix}*")
    redis.del(*keys) if keys.any?
  end

  it 'takes every shard while it is the only consumer' do
    supervisor.tick

    expect(supervisor.workers.keys).to eq([0, 1, 2, 3])
    expect(redis.get("#{prefix}events:0:lease")).to eq('consumer-1')
  end

  it 'leaves alone the shards another consumer already leased' do
    redis.set("#{prefix}events:0:lease", 'consumer-2', ex: 30)
    redis.set("#{prefix}events:1:lease", 'consumer-2', ex: 30)

    supervisor.tick

    expect(supervisor.workers.keys).to eq([2, 3])
  end

  it 'stops at its fair share once a peer shows up' do
    redis.set("#{prefix}consumer:consumer-2", { 'shards' => [] }.to_json, ex: 15)

    supervisor.tick

    expect(supervisor.workers.size).to eq(2)
  end

  it 'publishes a heartbeat the super admin screen can read' do
    supervisor.tick

    heartbeat = JSON.parse(redis.get("#{prefix}consumer:consumer-1"))
    expect(heartbeat['shards']).to eq([0, 1, 2, 3])
  end

  it 'drops a shard whose lease it lost, and leaves the new holder alone' do
    supervisor.tick
    redis.set("#{prefix}events:2:lease", 'consumer-2')

    supervisor.tick

    expect(supervisor.workers.keys).not_to include(2)
    # Neither renewed nor deleted: extending it would push consumer-2 off a shard it is
    # already reading, and deleting it would hand the shard to a third consumer.
    expect(redis.get("#{prefix}events:2:lease")).to eq('consumer-2')
    expect(redis.ttl("#{prefix}events:2:lease")).to eq(-1)
  end

  it 'gives shards back once a peer shows up to take them' do
    supervisor.tick
    expect(supervisor.workers.size).to eq(4)

    redis.set("#{prefix}consumer:consumer-2", { 'shards' => [] }.to_json, ex: 15)
    supervisor.tick

    # Without this the first consumer to start would hold every shard forever: the
    # newcomers find every lease taken and never get one.
    expect(supervisor.workers.keys).to eq([0, 1])
    expect(redis.get("#{prefix}events:3:lease")).to be_nil
  end

  it 'releases everything when it is asked to go quiet' do
    supervisor.tick

    supervisor.quiet

    expect(supervisor.workers).to be_empty
    expect(redis.get("#{prefix}events:0:lease")).to be_nil
  end
end
