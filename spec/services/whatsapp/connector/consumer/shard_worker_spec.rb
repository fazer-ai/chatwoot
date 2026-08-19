require 'rails_helper'

RSpec.describe Whatsapp::Connector::Consumer::ShardWorker, :redis_streams do
  subject(:worker) { described_class.new(0, 'consumer-1') }

  let(:prefix) { "watest#{SecureRandom.hex(4)}:" }
  let(:redis) { Redis.new(Redis::Config.app) }
  let(:session_id) { '9f1c0f4e-6a2b-4c8e-9d1a-2b3c4d5e6f70' }
  let(:channel) do
    create(:channel_whatsapp, provider: 'native', provider_config: { 'session_id' => session_id },
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:stream) { "#{prefix}events:0" }
  let(:frame) do
    {
      'v' => '1', 'id' => 'evt-1', 'type' => 'message.received', 'sid' => session_id,
      'epoch' => '1', 'seq' => '1', 'ts' => '1755440000123',
      'payload' => {
        message: {
          id: '3EB0AAAA0001', chat: { kind: 'phone', id: '5541999990000' },
          sender: { phone: '5541999990000', lid: '182736451928374', push_name: 'Ana Souza' },
          from_me: false, timestamp: 1_755_440_000_123, content: { type: 'text', body: 'oi' }
        }
      }.to_json
    }
  end

  around do |example|
    with_modified_env(WHATSAPP_CONNECTOR_REDIS_PREFIX: prefix) { example.run }
    keys = redis.keys("#{prefix}*")
    redis.del(*keys) if keys.any?
  end

  before { channel }

  it 'dispatches what it reads and acknowledges it' do
    redis.xadd(stream, frame)

    expect(worker.poll).to eq(1)

    expect(inbox.messages.pluck(:source_id)).to eq(['3EB0AAAA0001'])
    expect(redis.xpending(stream, described_class::Consumer::GROUP)['size']).to eq(0)
    expect(redis.get("#{prefix}cursor:#{session_id}")).to eq('1:1')
  end

  it 'skips an event whose session no inbox claims' do
    redis.xadd(stream, frame.merge('sid' => 'a-session-nobody-owns'))

    expect(worker.poll).to eq(1)
    expect(inbox.messages).to be_empty
  end

  it 'drops a redelivery it has already processed' do
    redis.xadd(stream, frame)
    worker.poll
    inbox.messages.destroy_all

    redis.xadd(stream, frame)
    worker.poll

    # The cursor, not the message row, is what makes this a no-op.
    expect(inbox.messages).to be_empty
  end

  it 'still processes an event from a newer epoch' do
    redis.xadd(stream, frame)
    worker.poll

    redis.xadd(stream, frame.merge('id' => 'evt-2', 'epoch' => '2', 'seq' => '1',
                                   'payload' => JSON.parse(frame['payload']).tap do |payload|
                                                  payload['message']['id'] = '3EB0AAAA0002'
                                                end.to_json))
    worker.poll

    expect(inbox.messages.pluck(:source_id)).to contain_exactly('3EB0AAAA0001', '3EB0AAAA0002')
  end

  it 'parks an entry it cannot read instead of blocking the shard' do
    redis.xadd(stream, frame.merge('payload' => 'not json'))

    expect(worker.poll).to eq(0)

    expect(redis.llen("#{prefix}dlq:events")).to eq(1)
    # Acknowledged even though it failed: the shard has to keep moving.
    expect(redis.xpending(stream, described_class::Consumer::GROUP)['size']).to eq(0)
  end

  it 'retries a failure that a second attempt could fix' do
    stub_const("#{described_class}::RETRY_WAITS", [0, 0])
    attempts = 0
    allow(Whatsapp::Session::Inbound::Dispatcher).to receive(:dispatch).and_wrap_original do |original, *args|
      attempts += 1
      raise ActiveRecord::Deadlocked, 'deadlock detected' if attempts < 3

      original.call(*args)
    end
    redis.xadd(stream, frame)

    expect(worker.poll).to eq(1)

    expect(attempts).to eq(3)
    expect(inbox.messages.pluck(:source_id)).to eq(['3EB0AAAA0001'])
    expect(redis.llen("#{prefix}dlq:events")).to eq(0)
  end

  it 'parks a failure that outlives the retries' do
    stub_const("#{described_class}::RETRY_WAITS", [0])
    allow(Whatsapp::Session::Inbound::Dispatcher).to receive(:dispatch).and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
    redis.xadd(stream, frame)

    expect(worker.poll).to eq(0)

    expect(Whatsapp::Session::Inbound::Dispatcher).to have_received(:dispatch).twice
    expect(redis.llen("#{prefix}dlq:events")).to eq(1)
  end

  it 'waits out the chat lock instead of spending the ordinary retry budget on it' do
    stub_const("#{described_class}::RETRY_WAITS", [])
    stub_const("#{described_class}::BUSY_WAITS", [0, 0])
    attempts = 0
    allow(Whatsapp::Session::Inbound::Dispatcher).to receive(:dispatch).and_wrap_original do |original, *args|
      attempts += 1
      raise Whatsapp::Session::Inbound::Locks::Busy, 'a group sync holds it' if attempts < 3

      original.call(*args)
    end
    redis.xadd(stream, frame)

    expect(worker.poll).to eq(1)

    expect(attempts).to eq(3)
    expect(inbox.messages.pluck(:source_id)).to eq(['3EB0AAAA0001'])
  end

  it 'leaves an entry pending when it is stopped mid-retry' do
    stub_const("#{described_class}::RETRY_WAITS", [0, 0])
    allow(Whatsapp::Session::Inbound::Dispatcher).to receive(:dispatch) do
      worker.stop
      raise ActiveRecord::Deadlocked, 'deadlock detected'
    end
    redis.xadd(stream, frame)

    expect(worker.poll).to eq(0)

    # Neither acknowledged nor dead-lettered: whoever takes the shard next claims it by
    # idle time and gets to try the event itself.
    expect(redis.xpending(stream, described_class::Consumer::GROUP)['size']).to eq(1)
    expect(redis.llen("#{prefix}dlq:events")).to eq(0)
  end

  # Every database call this thread makes has to sit inside the executor: it is a
  # long-lived thread outside the request cycle, and a connection checked out here is
  # only returned when the wrap closes.
  it 'runs each attempt inside the Rails executor' do
    stub_const("#{described_class}::RETRY_WAITS", [0])
    allow(Rails.application.executor).to receive(:wrap).and_call_original
    allow(Whatsapp::Session::Inbound::Dispatcher).to receive(:dispatch).and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
    redis.xadd(stream, frame)

    worker.poll

    expect(Rails.application.executor).to have_received(:wrap).twice
  end

  it 'takes over what a dead consumer left unacknowledged' do
    redis.xadd(stream, frame)
    redis.xgroup(:create, stream, described_class::Consumer::GROUP, '0', mkstream: true)
    redis.xreadgroup(described_class::Consumer::GROUP, 'consumer-dead', stream, '>')

    stub_const("#{described_class}::IDLE_CLAIM_MS", 0)
    expect(worker.poll).to eq(1)

    expect(inbox.messages.pluck(:source_id)).to eq(['3EB0AAAA0001'])
  end
end
