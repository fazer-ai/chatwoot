require 'rails_helper'

RSpec.describe SuperAdmin::HealthScore::Metrics::HandoffRate do
  let(:on) { Date.current }
  let(:account) { create(:account, ai_status_uses_attribute: true) }
  let(:agent) { create(:user, account: account) }

  describe 'attribute mode' do
    it 'inverts the rate so lower handoff yields a higher score' do
      # 30 AI-active conversations, 6 with a human outgoing message → rate 20%
      conversations = create_list(:conversation, 30, account: account, ai_enabled: true, created_at: 5.days.ago)
      conversations.first(6).each do |conv|
        create(:message, conversation: conv, account: account, message_type: :outgoing, sender: agent, sender_type: 'User')
      end

      result = described_class.new(account, on: on).compute

      expect(result[:sub_score]).to eq(80)
      expect(result.dig(:raw, :rate_pct)).to be_within(0.001).of(0.2)
      expect(result.dig(:raw, :total_conversations)).to eq(30)
      expect(result.dig(:raw, :handoff_count)).to eq(6)
    end

    it 'flags insufficient volume below 30 conversations' do
      create_list(:conversation, 10, account: account, ai_enabled: true, created_at: 5.days.ago)

      result = described_class.new(account, on: on).compute

      expect(result).to include(missing: true, reason: 'insufficient_volume')
    end
  end

  describe 'legacy label mode' do
    let(:account) { create(:account) }

    it 'treats conversations without agente-off as AI-active' do
      create_list(:conversation, 30, account: account, created_at: 5.days.ago)
      # 30 with the label → excluded from the AI-active scope, shouldn't drag handoff up
      create_list(:conversation, 30, account: account, created_at: 5.days.ago).each do |c|
        c.update!(label_list: 'agente-off')
      end

      result = described_class.new(account, on: on).compute

      expect(result).to include(missing: false)
      expect(result.dig(:raw, :total_conversations)).to eq(30)
    end
  end
end
