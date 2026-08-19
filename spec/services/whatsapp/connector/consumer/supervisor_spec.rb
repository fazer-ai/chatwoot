require 'rails_helper'

RSpec.describe Whatsapp::Connector::Consumer::Supervisor, :redis_streams do
  subject(:supervisor) { described_class.new(consumer_id: 'consumer-1', worker_class: worker_class) }

  let(:prefix) { "watest#{SecureRandom.hex(4)}:" }
  let(:redis) { Redis.new(Redis::Config.app) }
  # A worker that only reports whether it is alive: the claim loop is what is under test.
  let(:worker_class) do
    Class.new do
      attr_reader :shard, :queue

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
    # Told to stop, but the lease is still ours until the thread is out.
    expect(redis.get("#{prefix}events:3:lease")).to eq('consumer-1')

    supervisor.tick

    expect(redis.get("#{prefix}events:3:lease")).to be_nil
  end

  # The window this closes: a handler that runs longer than the supervisor is willing to
  # wait used to have its lease dropped anyway, and a peer would then read the shard
  # alongside a thread that was still writing rows and moving the session cursor.
  it 'keeps the lease of a worker that has not finished its current entry' do
    supervisor.tick
    stuck = supervisor.workers[0]
    allow(stuck).to receive(:stop) # the thread stays parked in run

    supervisor.quiet
    supervisor.tick

    expect(redis.get("#{prefix}events:0:lease")).to eq('consumer-1')
    expect(redis.get("#{prefix}events:1:lease")).to be_nil

    stuck.queue << :stop # let it out, so the shutdown in the around hook is not a wait
  end

  it 'reads as many shards as the connector says it publishes' do
    redis.hset("#{prefix}meta", 'event_shards', '2')

    supervisor.tick

    # The local setting says four; following it would leave the connector's own streams
    # unread, and every inbox sharded onto them silently deaf.
    expect(supervisor.workers.keys).to eq([0, 1])
  end

  it 'releases everything when it is asked to go quiet' do
    supervisor.tick

    supervisor.quiet

    expect(supervisor.workers).to be_empty
    # The lease follows the thread out, on the tick after it exits: quiet returns without
    # waiting, because Sidekiq calls it before its own shutdown clock starts.
    supervisor.tick
    expect(redis.get("#{prefix}events:0:lease")).to be_nil
  end

  # Rebalancing counted the leases it still held rather than the shards it was reading,
  # so a worker that had not exited yet was counted again on the next tick and took
  # another one down with it, until nothing was reading at all.
  it 'stops giving shards up once it is down to its share' do
    supervisor.tick
    redis.set("#{prefix}consumer:consumer-2", { 'shards' => [] }.to_json, ex: 15)
    stuck = supervisor.workers[3]
    allow(stuck).to receive(:stop) # its thread outlives the rebalance that dropped it

    supervisor.tick
    supervisor.tick

    expect(supervisor.workers.keys).to eq([0, 1])

    stuck.queue << :stop
  end

  # A process on its way out is not a peer. Counting it made the replacement claim half
  # the shards and leave the rest unread until the heartbeat lapsed.
  it 'takes itself out of the registry while it drains' do
    supervisor.tick
    expect(redis.get("#{prefix}consumer:consumer-1")).to be_present

    supervisor.quiet
    supervisor.tick

    expect(redis.get("#{prefix}consumer:consumer-1")).to be_nil
  end

  it 'claims nothing more once it is draining' do
    supervisor.quiet

    supervisor.tick

    expect(supervisor.workers).to be_empty
    expect(redis.get("#{prefix}events:0:lease")).to be_nil
  end
end
