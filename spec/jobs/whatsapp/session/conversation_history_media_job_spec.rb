require 'rails_helper'

RSpec.describe Whatsapp::Session::ConversationHistoryMediaJob do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  let(:conversation) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:other) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:pending_media) { Whatsapp::Session::Model::Content::Media.new(kind: 'image', mime: 'image/jpeg').to_h }

  before { allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend) }

  def pending(conversation, source_id, at)
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: source_id, created_at: at,
                     content_attributes: { 'is_unsupported' => true, 'history_media' => true, 'pending_media' => pending_media })
  end

  # The window is the inbox's automatic fetch; somebody asking for one conversation wants
  # all of it, and nothing of the conversation next to it.
  it 'attaches every missing file of the conversation, whatever its age, and only of it' do
    old = pending(conversation, 'OLD1', 400.days.ago)
    recent = pending(conversation, 'NEW1', 1.day.ago)
    elsewhere = pending(other, 'ELSE1', 1.day.ago)
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: 'TEXT1', content: 'oi')

    described_class.perform_now(conversation)

    expect([old, recent].map { |message| message.reload.attachments.count }).to eq([1, 1])
    expect(elsewhere.reload.attachments).to be_empty
    expect(backend.commands.map(&:message_id)).to contain_exactly('OLD1', 'NEW1')
  end

  it 'asks only for what a previous run did not get' do
    pending(conversation, 'ONCE1', 1.day.ago)
    described_class.perform_now(conversation)

    described_class.perform_now(conversation)

    expect(backend.commands.map(&:message_id)).to eq(['ONCE1'])
  end

  # A group with thousands of files must not hold one worker for all of them.
  it 'downloads a batch per run and hands the rest to the next one' do
    Array.new(described_class::BATCH + 2) { |index| pending(conversation, "B#{index}", index.hours.ago) }

    described_class.perform_now(conversation)
    expect(backend.commands.size).to eq(described_class::BATCH)

    continuation = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |job| job['job_class'] == described_class.name }
    described_class.perform_now(conversation, continuation['arguments'].last)

    expect(backend.commands.size).to eq(described_class::BATCH + 2)
    expect(conversation.messages.where.missing(:attachments)).to be_empty
  end

  it 'comes back from where it was when the instance has no history slot free' do
    pending(conversation, 'WAIT1', 1.day.ago)
    allow(Whatsapp::Session::Inbound::ImportSlots).to receive(:concurrency).and_return(0)

    described_class.perform_now(conversation, 99)

    expect(backend.commands).to be_empty
    expect(described_class).to have_been_enqueued.with(conversation, 99)
  end
end
