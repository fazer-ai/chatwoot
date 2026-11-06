require 'rails_helper'

# Upstream pins these two examples to 2026-10-31, before the work item its before block builds
# at the current time: past that date they fail everywhere. Superseded by these copies, which
# travel to the last day of next month instead (fazer_ai_ee/spec/support/superseded_upstream_examples.rb).
RSpec.describe ConversationMonitors::Evaluator do
  subject(:evaluate) { -> { described_class.new(work.reload).perform } }

  let(:account) { create(:account) }
  let(:monitor) { create(:conversation_monitor, account: account) }
  let(:second) { create(:conversation_monitor, account: account, condition: 'Mentions WhatsApp BSUID') }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation, content: 'Please refund my order') }
  let(:work) { ConversationMonitors::WorkItem.find_by!(conversation_id: conversation.id) }
  let(:answers) { { monitor.id.to_s => { type: 'noul', noul: 0.95 }, second.id.to_s => { type: 'noul', noul: 0.05 } } }
  let(:response_body) { { model: 'typesafe/jev-1.13-20260917', answers: answers, usage: { input_tokens: 100 } } }
  let(:endpoint) { ConversationMonitors::Configuration.endpoint }

  before do
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPENROUTER_API_KEY').update!(value: 'test-key')
    account.enable_features!('reports', 'conversation_monitors')
    monitor
    second
    message
    work.update!(due_at: Time.current)
    stub_request(:post, endpoint).to_return(status: 200, body: response_body.to_json)
  end

  it 'holds exhausted accounts until next month and preserves full history across new input' do
    # The last day of next month: always after the work item built by the before block, with 19 earlier days in it.
    travel_to(1.month.from_now.utc.end_of_month.change(hour: 12))
    now = Time.current.utc
    reset = now.beginning_of_month.next_month
    (1..19).each do |days_ago|
      ConversationMonitors::DailyUsage.create!(account: account, usage_date: now.to_date - days_ago, calls_count: 500_000)
    end
    ConversationMonitors::DailyUsage.create!(account: account, usage_date: now.to_date, calls_count: 500_000, limit_reached_at: now)
    work.update!(attempts: 10)

    evaluate.call

    expect(WebMock).not_to have_requested(:post, endpoint)
    expect(work.reload).to have_attributes(error_code: 'monthly_limit', due_at: be_between(reset, reset + 4.hours),
                                           full_history_revision: be > work.processed_revision)
    expect(monitor.evaluations.sole.error_code).to eq('monthly_limit')
    due_at = work.due_at
    create(:message, account: account, conversation: conversation, content: 'Another message during the quota hold')
    expect(work.reload).to have_attributes(due_at: due_at, error_code: 'monthly_limit')

    travel_to(due_at + 1.second) do
      evaluate.call
      expect(WebMock).to have_requested(:post, endpoint).once
      expect(monitor.evaluations.sole.status).to eq('matched')
      expect(ConversationMonitors::Usage.new(account.id).snapshot[:used]).to eq(1)
    end
  end

  it 'preserves the monthly hold through an earlier batch provider cooldown after the reset' do
    travel_to(1.month.from_now.utc.end_of_month.change(hour: 23, min: 55))
    now = Time.current.utc
    reset = now.beginning_of_month.next_month
    (1..19).each do |days_ago|
      ConversationMonitors::DailyUsage.create!(account: account, usage_date: now.to_date - days_ago, calls_count: 500_000)
    end
    ConversationMonitors::DailyUsage.create!(account: account, usage_date: now.to_date, calls_count: 499_999)
    create_list(:conversation_monitor, 18, account: account, condition: '退款' * 250, created_at: 1.minute.ago)
    create(:message, account: account, conversation: conversation, content: 'x' * 30_000)
    stub_request(:post, endpoint).to_return(status: 429, headers: { 'Retry-After' => '7200' })

    evaluator = described_class.new(work.reload)
    allow(evaluator).to receive(:rand).and_return(0)
    evaluator.perform

    expect(WebMock).to have_requested(:post, endpoint).once
    retry_at = 2.hours.from_now
    expect(work.reload).to have_attributes(error_code: 'monthly_limit', due_at: retry_at,
                                           full_history_revision: be > work.processed_revision)
    expect(ConversationMonitors::Usage.new(account.id).snapshot[:used]).to eq(10_000_000)

    create(:message, account: account, conversation: conversation, content: 'Another question during the monthly cooldown')
    expect(work.reload).to have_attributes(error_code: 'monthly_limit', due_at: retry_at)
    travel_to(reset + 31.minutes)

    expect { ConversationMonitors::ProcessJob.perform_now(conversation.id) }.not_to have_enqueued_job(ConversationMonitors::ProcessJob)
    expect(WebMock).to have_requested(:post, endpoint).once
    expect(ConversationMonitors::Usage.new(account.id).snapshot[:used]).to eq(0)
  end
end
