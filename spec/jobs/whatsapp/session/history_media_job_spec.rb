require 'rails_helper'

RSpec.describe Whatsapp::Session::HistoryMediaJob do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  let(:conversation) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:chat) { Whatsapp::Session::Model::Address.group('120363000000000001') }
  let(:queue) { Whatsapp::Session::HistoryMedia.queue_key(inbox) }

  before { allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend) }

  after do
    Redis::Alfred.delete(queue)
    Redis::Alfred.delete(described_class.scheduled_key(inbox))
  end

  def pending(source_id, at)
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: source_id, created_at: at,
                     content_attributes: { 'is_unsupported' => true, 'history_media' => true, 'imported' => true,
                                           'pending_media' => Whatsapp::Session::Model::Content::Media.new(kind: 'image', mime: 'image/jpeg').to_h,
                                           'pending_chat' => chat.to_h })
  end

  def queue_up(*messages)
    messages.each { |message| Redis::Alfred.zadd(queue, message.created_at.to_f, message.id) }
  end

  it 'attaches the files newest first, asking under the chat the history named' do
    older = pending('OLD1', 10.days.ago)
    newer = pending('NEW1', 1.day.ago)
    queue_up(older, newer)

    described_class.perform_now(inbox)

    expect(backend.commands.map(&:message_id)).to eq(%w[NEW1 OLD1])
    expect(backend.commands.map { |command| command.chat.to_jid }.uniq).to eq([chat.to_jid])
    expect([older.reload, newer.reload].map { |message| message.attachments.count }).to eq([1, 1])
    expect(newer.content_attributes).not_to include('history_media', 'is_unsupported')
  end

  # Thousands of files must not hold one worker for hours, nor sit on the queue at once.
  it 'hands the queue back after a batch and comes back for the rest' do
    queue_up(*Array.new(described_class::BATCH + 2) { |index| pending("M#{index}", index.hours.ago) })

    described_class.perform_now(inbox)

    expect(backend.commands.size).to eq(described_class::BATCH)
    expect(Redis::Alfred.zcard(queue)).to eq(2)
    expect(described_class).to have_been_enqueued.with(inbox).exactly(:once)
  end

  it 'skips a file that fell out of a window narrowed after it was queued' do
    message = pending('OLD2', 20.days.ago)
    queue_up(message)
    channel.update!(provider_config: channel.provider_config.merge('history_media_days' => 7))

    described_class.perform_now(inbox)

    expect(backend.commands).to be_empty
    expect(message.reload.attachments).to be_empty
  end

  it 'does not ask again for a file the provider already gave up on' do
    message = pending('GONE1', 1.day.ago)
    message.update!(content_attributes: message.content_attributes.except('history_media'))
    queue_up(message)

    described_class.perform_now(inbox)

    expect(backend.commands).to be_empty
  end

  it 'stops asking once the inbox turns the automatic fetch off' do
    queue_up(pending('OFF1', 1.day.ago))
    channel.update!(provider_config: channel.provider_config.merge('history_media_fetch' => false))

    described_class.perform_now(inbox)

    expect(backend.commands).to be_empty
    expect(Redis::Alfred.exists?(described_class.scheduled_key(inbox))).to be(false)
  end

  [Whatsapp::Session::Errors::ProviderUnavailable, Whatsapp::Session::Errors::RateLimited].each do |error|
    it "keeps the file queued and comes back later on #{error.name.demodulize}" do
      message = pending('DOWN1', 1.day.ago)
      queue_up(message)
      allow(backend).to receive(:download_media).and_raise(error, 'try later')

      described_class.perform_now(inbox)

      expect(Redis::Alfred.zcard(queue)).to eq(1)
      expect(message.reload.content_attributes).to include('history_media' => true)
      expect(described_class).to have_been_enqueued.with(inbox)
    end
  end

  # One drain per inbox is what keeps its history to one download at a time.
  it 'queues a single run however many files are tracked while one is pending' do
    3.times { |index| Whatsapp::Session::HistoryMedia.track(pending("T#{index}", index.hours.ago)) }

    expect(described_class).to have_been_enqueued.with(inbox).exactly(:once)
  end

  it 'lets the next file start a run once the queue has drained' do
    Whatsapp::Session::HistoryMedia.track(pending('LAST1', 1.day.ago))
    described_class.perform_now(inbox)

    Whatsapp::Session::HistoryMedia.track(pending('NEXT1', 2.days.ago))

    expect(described_class).to have_been_enqueued.with(inbox).exactly(:twice)
  end
end
