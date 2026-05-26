require 'rails_helper'

RSpec.describe SuperAdmin::HealthScore::Metrics::AiActiveRate do
  let(:on) { Date.current }

  describe 'implementation phase' do
    let(:account) { create(:account, ai_status_uses_attribute: true) }

    it 'returns missing for accounts younger than 45 days' do
      account.update!(created_at: 10.days.ago)

      result = described_class.new(account, on: on).compute

      expect(result).to include(missing: true, reason: 'account_in_implementation_phase')
      expect(result.dig(:raw, :account_age_days)).to eq(10)
    end
  end

  describe 'mature account in attribute mode' do
    let(:account) { create(:account, ai_status_uses_attribute: true) }

    before { account.update!(created_at: 120.days.ago) }

    it 'returns a score reflecting the current rate plus the trend' do
      # Current window (last 30d): 60/100 AI active = 60%
      create_list(:conversation, 60, account: account, ai_enabled: true, created_at: 5.days.ago)
      create_list(:conversation, 40, account: account, ai_enabled: false, created_at: 5.days.ago)
      # Prior window (days 30-60 ago): 80/100 AI active = 80%
      create_list(:conversation, 80, account: account, ai_enabled: true, created_at: 45.days.ago)
      create_list(:conversation, 20, account: account, ai_enabled: false, created_at: 45.days.ago)

      result = described_class.new(account, on: on).compute

      # sub_score = (0.60 + 0.5 * (0.60 - 0.80)) * 100 = 50
      expect(result[:sub_score]).to eq(50)
      expect(result.dig(:raw, :trend_applied)).to be true
      expect(result.dig(:raw, :mode)).to eq('attribute')
    end

    it 'flags insufficient volume when fewer than 50 conversations land in the window' do
      create_list(:conversation, 10, account: account, ai_enabled: true, created_at: 5.days.ago)

      result = described_class.new(account, on: on).compute

      expect(result).to include(missing: true, reason: 'insufficient_volume')
    end
  end

  describe 'early operational phase (45-60 days)' do
    let(:account) { create(:account, ai_status_uses_attribute: true) }

    before { account.update!(created_at: 50.days.ago) }

    it 'computes score from current rate only, without trend' do
      create_list(:conversation, 80, account: account, ai_enabled: true, created_at: 5.days.ago)
      create_list(:conversation, 20, account: account, ai_enabled: false, created_at: 5.days.ago)

      result = described_class.new(account, on: on).compute

      expect(result[:sub_score]).to eq(80)
      expect(result.dig(:raw, :trend_applied)).to be false
    end
  end

  describe 'legacy label mode' do
    let(:account) { create(:account) }

    before { account.update!(created_at: 120.days.ago, ai_status_uses_attribute: false) }

    it 'counts conversations without the agente-off label as AI active' do
      create_list(:conversation, 70, account: account, created_at: 5.days.ago)
      create_list(:conversation, 30, account: account, created_at: 5.days.ago).each do |c|
        c.update!(label_list: 'agente-off')
      end
      # Pad prior window so trend doesn't penalize
      create_list(:conversation, 70, account: account, created_at: 45.days.ago)
      create_list(:conversation, 30, account: account, created_at: 45.days.ago).each do |c|
        c.update!(label_list: 'agente-off')
      end

      result = described_class.new(account, on: on).compute

      expect(result[:sub_score]).to eq(70)
      expect(result.dig(:raw, :mode)).to eq('legacy_label')
    end
  end
end
