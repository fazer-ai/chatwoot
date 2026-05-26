require 'rails_helper'

RSpec.describe SuperAdmin::HealthScore::Metrics::DailyAgentActivity do
  # Pick a Monday so the 14d window covers exactly 10 business days.
  let(:on) { Date.new(2026, 4, 13) }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  it 'returns 100 when every business day in the last 14 has agent activity' do
    business_days = ((on - 13)..on).reject { |d| d.saturday? || d.sunday? }
    business_days.each do |day|
      create(:message, conversation: conversation, account: account, message_type: :outgoing,
                       sender: agent, sender_type: 'User', created_at: day.in_time_zone.change(hour: 10))
    end

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(100)
    expect(result.dig(:raw, :active_days)).to eq(business_days.size)
    expect(result.dig(:raw, :business_days)).to eq(business_days.size)
  end

  it 'returns 50 when half the business days have activity' do
    business_days = ((on - 13)..on).reject { |d| d.saturday? || d.sunday? }
    business_days.first(business_days.size / 2).each do |day|
      create(:message, conversation: conversation, account: account, message_type: :outgoing,
                       sender: agent, sender_type: 'User', created_at: day.in_time_zone.change(hour: 10))
    end

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(50)
  end

  it 'ignores incoming messages and contact-sent messages' do
    create(:message, conversation: conversation, account: account, message_type: :incoming,
                     sender_type: 'Contact', created_at: on.in_time_zone.change(hour: 10))

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(0)
    expect(result.dig(:raw, :active_days)).to eq(0)
  end
end
