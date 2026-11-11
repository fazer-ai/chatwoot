require 'rails_helper'

# rubocop:disable RSpec/DescribeClass -- the subject is the Listener patch in
# config/initializers/actioncable.rb, exercised through the adapter against a real Redis.
describe 'Action Cable Redis listener recovery', :redis_streams do
  let(:server) do
    ActionCable::Server::Base.new.tap do |cable_server|
      cable_server.config.cable = {
        adapter: 'redis',
        url: ENV.fetch('REDIS_URL'),
        channel_prefix: "spec_cable_listener_#{SecureRandom.hex(4)}",
        # A budget of two retries: stock Rails gives up on the third consecutive failure.
        reconnect_attempts: [0, 0.05]
      }
      cable_server.config.logger = Logger.new(nil)
    end
  end
  let(:adapter) { ActionCable::SubscriptionAdapter::Redis.new(server) }
  let(:events) { Queue.new }
  let(:attempts) { Queue.new }
  let(:outage) { { on: false } }
  let(:control) { Redis.new(url: ENV.fetch('REDIS_URL')) }

  before do
    allow(adapter).to receive(:redis_connection_for_subscriptions).and_wrap_original do |original|
      attempts << :attempt
      raise Redis::CannotConnectError, 'simulated outage' if outage[:on]

      original.call
    end
  end

  after do
    outage[:on] = false
    adapter.shutdown
    server.event_loop.stop
    control.close
  end

  # Returns the message callback, which is what unsubscribe takes to drop that subscriber.
  def subscribe(channel, name)
    on_message = ->(message) { events << [name, message] }
    adapter.subscribe(channel, on_message, -> { events << [name, :confirmed] })
    on_message
  end

  # Waits for `count` failed connection attempts. Past the budget of two retries stock Rails makes no more.
  def wait_for_failed_attempts(count)
    count.times { expect(attempts.pop(timeout: 5)).to eq(:attempt) }
  end

  # Earlier examples in this process leave connections under the same name, so drop them all.
  def kill_listener_connection
    listeners = control.call('CLIENT', 'LIST').lines.grep(/ name=ActionCable-PID-#{Process.pid} /)
    listeners.each { |line| control.call('CLIENT', 'KILL', 'ID', line[/\bid=(\d+)/, 1]) }
  end

  # Broadcasts sent before the listener has resubscribed are lost, so publish until one lands.
  def broadcast_until_delivered(channel)
    20.times do |i|
      adapter.broadcast(channel, "ping-#{i}")
      event = events.pop(timeout: 0.25)
      return event if event
    end
    nil
  end

  it 'confirms a subscription made while Redis stays unreachable past the retry budget' do
    outage[:on] = true
    subscribe('room', :first)
    wait_for_failed_attempts(3)
    outage[:on] = false

    expect(events.pop(timeout: 5)).to eq([:first, :confirmed])
    adapter.broadcast('room', 'hello')
    expect(events.pop(timeout: 5)).to eq([:first, 'hello'])
  end

  it 'delivers again to a channel subscribed before the connection dropped past the retry budget' do
    subscribe('room', :first)
    expect(events.pop(timeout: 5)).to eq([:first, :confirmed])
    attempts.clear

    outage[:on] = true
    kill_listener_connection
    wait_for_failed_attempts(2)
    outage[:on] = false

    expect(broadcast_until_delivered('room')).to match([:first, /\Aping-\d+\z/])
  end

  it 'keeps waiting the last configured interval between retries past the budget' do
    outage[:on] = true
    subscribe('room', :first)
    wait_for_failed_attempts(3)
    attempts.clear
    # 0.05s apart, a second holds about 20 attempts; an unpaced loop makes thousands.
    sleep 1

    expect(attempts.size).to be_between(5, 30)
  end

  it 'stops retrying when the server shuts down during the outage' do
    outage[:on] = true
    subscribe('room', :first)
    wait_for_failed_attempts(3)

    expect(Thread.new { adapter.shutdown }.join(2)).to be_truthy
  end

  it 'confirms a channel re-added during the outage, not the subscription that left' do
    outage[:on] = true
    left = subscribe('room', :left)
    wait_for_failed_attempts(3)
    adapter.unsubscribe('room', left)
    subscribe('room', :rejoined)
    outage[:on] = false

    expect(events.pop(timeout: 5)).to eq([:rejoined, :confirmed])
    adapter.broadcast('room', 'hello')
    expect(events.pop(timeout: 5)).to eq([:rejoined, 'hello'])
    expect(events.pop(timeout: 0.5)).to be_nil
  end
end
# rubocop:enable RSpec/DescribeClass
