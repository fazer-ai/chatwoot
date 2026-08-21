require 'rails_helper'

RSpec.describe SidekiqDeathHandler do
  let(:exception) { StandardError.new('the provider never answered') }

  def job_for(class_name, arguments)
    { 'class' => 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper',
      'wrapped' => class_name,
      'args' => [{ 'arguments' => arguments }] }
  end

  before { allow(Rails.logger).to receive(:error) }

  # The dead set held hundreds of failed sends nobody had been told about, so the bug was
  # found by the customer complaining rather than by monitoring.
  it 'reports a dead job' do
    described_class.call(job_for('SomeJob', [42]), exception)

    expect(Rails.logger).to have_received(:error).with(/\[SIDEKIQ\]\[DEAD\] SomeJob/)
  end

  # An opaque message id is not actionable at 3am; the account and inbox are.
  it 'names the account, inbox and conversation for a dead reply' do
    message = create(:message, message_type: :outgoing)

    described_class.call(job_for('SendReplyJob', [message.id]), exception)

    expect(Rails.logger).to have_received(:error).with(
      /account_id=#{message.account_id} inbox_id=#{message.inbox_id} conversation_id=#{message.conversation_id}/
    )
  end

  it 'still reports when the message is already gone' do
    described_class.call(job_for('SendReplyJob', [-1]), exception)

    expect(Rails.logger).to have_received(:error).with(/\[SIDEKIQ\]\[DEAD\] SendReplyJob/)
  end

  it 'reports a plain Sidekiq worker payload by class and jid' do
    described_class.call({ 'class' => 'PlainWorker', 'args' => [7], 'jid' => 'abc123', 'queue' => 'low' }, exception)

    expect(Rails.logger).to have_received(:error).with(/PlainWorker jid=abc123 queue=low/)
  end

  # Arguments are job payloads: WebhookJob carries the customer's message body and its
  # signing secret positionally, so dumping them here would put message content and a
  # credential into the log aggregator on any unexpected terminal failure. The jid is
  # enough to pull the full payload from the dead set, where access is already controlled.
  it 'never writes job arguments to the log' do
    described_class.call(
      { 'class' => 'WebhookJob', 'args' => ['https://hook.example', { 'content' => 'private' }, 's3cr3t'], 'jid' => 'abc123' },
      exception
    )

    expect(Rails.logger).not_to have_received(:error).with(/s3cr3t|private/)
    expect(Rails.logger).to have_received(:error).with(/WebhookJob jid=abc123/)
  end

  it 'sends the exception to the tracker with the account attached' do
    message = create(:message, message_type: :outgoing)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.call(job_for('SendReplyJob', [message.id]), exception)

    expect(ChatwootExceptionTracker).to have_received(:new).with(exception, account: message.account)
  end

  # A death handler that raises takes down the reporting for the job it was reporting.
  it 'never raises out of the handler' do
    allow(Message).to receive(:find_by).and_raise(StandardError, 'db down')

    expect { described_class.call(job_for('SendReplyJob', [1]), exception) }.not_to raise_error
  end
end
