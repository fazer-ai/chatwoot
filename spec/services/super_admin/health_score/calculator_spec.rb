require 'rails_helper'

RSpec.describe SuperAdmin::HealthScore::Calculator do
  let(:on) { Date.current }
  let(:account) { create(:account, ai_status_uses_attribute: true) }

  before { account.update!(created_at: 120.days.ago) }

  describe '#perform' do
    it 'persists a snapshot with the weighted score and a full breakdown' do
      # Stub metrics to make the math explicit
      stub_metric(SuperAdmin::HealthScore::Metrics::AiActiveRate, sub_score: 80, raw: { mode: 'attribute' })
      stub_metric(SuperAdmin::HealthScore::Metrics::HandoffRate, sub_score: 70, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::InboxUptime, sub_score: 100, raw: { all_disconnected: false })
      stub_metric(SuperAdmin::HealthScore::Metrics::DailyAgentActivity, sub_score: 60, raw: { active_days: 6 })
      stub_metric(SuperAdmin::HealthScore::Metrics::ManagerEngagement, sub_score: 100, raw: { recent_login: true })

      record = described_class.new(account, on: on).perform

      # 80*30 + 70*10 + 100*25 + 60*25 + 100*10 = 8100 / 100 = 81
      expect(record.score).to eq(81)
      expect(record.captured_on).to eq(on)
      expect(record.breakdown.dig('groups', 'outcomes', 'sub_score_normalized')).to eq(78) # (80*30 + 70*10) / 40
      expect(record.breakdown.dig('groups', 'operational', 'sub_score_normalized')).to eq(100)
      expect(record.breakdown.dig('groups', 'engagement', 'sub_score_normalized')).to eq(71) # (60*25 + 100*10) / 35
      expect(record.breakdown['phase']).to eq('mature')
    end

    it 'redistributes weight when a metric is missing' do
      stub_metric(SuperAdmin::HealthScore::Metrics::AiActiveRate, sub_score: 80, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::HandoffRate, sub_score: 70, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::InboxUptime, sub_score: 100, raw: { all_disconnected: false })
      stub_metric(SuperAdmin::HealthScore::Metrics::DailyAgentActivity, sub_score: 60, raw: { active_days: 6 })
      stub_missing_metric(SuperAdmin::HealthScore::Metrics::ManagerEngagement, reason: 'no_manager_role')

      record = described_class.new(account, on: on).perform

      # Available weight: 30 + 10 + 25 + 25 = 90
      # Weighted sum: 80*30 + 70*10 + 100*25 + 60*25 = 7100
      # 7100 / 90 = 78.88 -> rounded 79
      expect(record.score).to eq(79)
      expect(record.breakdown.dig('metrics', 'manager_engagement', 'missing')).to be true
      expect(record.breakdown.dig('groups', 'engagement', 'sub_score_normalized')).to eq(60)
    end

    it 'caps the score at 40 when all WhatsApp inboxes are disconnected' do
      stub_metric(SuperAdmin::HealthScore::Metrics::AiActiveRate, sub_score: 100, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::HandoffRate, sub_score: 100, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::InboxUptime, sub_score: 0, raw: { all_disconnected: true })
      stub_metric(SuperAdmin::HealthScore::Metrics::DailyAgentActivity, sub_score: 100, raw: { active_days: 10 })
      stub_metric(SuperAdmin::HealthScore::Metrics::ManagerEngagement, sub_score: 100, raw: {})

      record = described_class.new(account, on: on).perform

      expect(record.score).to be <= 40
      expect(record.breakdown['kill_clause']).to eq('all_whatsapp_inboxes_disconnected')
    end

    it 'caps the score at 30 when there is zero agent activity' do
      stub_metric(SuperAdmin::HealthScore::Metrics::AiActiveRate, sub_score: 100, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::HandoffRate, sub_score: 100, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::InboxUptime, sub_score: 100, raw: { all_disconnected: false })
      stub_metric(SuperAdmin::HealthScore::Metrics::DailyAgentActivity, sub_score: 0, raw: { active_days: 0 })
      stub_metric(SuperAdmin::HealthScore::Metrics::ManagerEngagement, sub_score: 100, raw: {})

      record = described_class.new(account, on: on).perform

      expect(record.score).to be <= 30
      expect(record.breakdown['kill_clause']).to eq('no_agent_activity')
    end

    it 'upserts when re-run on the same day' do
      stub_metric(SuperAdmin::HealthScore::Metrics::AiActiveRate, sub_score: 80, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::HandoffRate, sub_score: 80, raw: {})
      stub_metric(SuperAdmin::HealthScore::Metrics::InboxUptime, sub_score: 80, raw: { all_disconnected: false })
      stub_metric(SuperAdmin::HealthScore::Metrics::DailyAgentActivity, sub_score: 80, raw: { active_days: 8 })
      stub_metric(SuperAdmin::HealthScore::Metrics::ManagerEngagement, sub_score: 80, raw: {})

      first = described_class.new(account, on: on).perform
      second = described_class.new(account, on: on).perform

      expect(second.id).to eq(first.id)
      expect(AccountHealthScore.where(account: account, captured_on: on).count).to eq(1)
    end
  end

  def stub_metric(klass, sub_score:, raw:)
    instance = instance_double(klass, compute: { sub_score: sub_score, raw: raw, missing: false, reason: nil })
    allow(klass).to receive(:new).and_return(instance)
  end

  def stub_missing_metric(klass, reason:)
    instance = instance_double(klass, compute: { sub_score: nil, raw: {}, missing: true, reason: reason })
    allow(klass).to receive(:new).and_return(instance)
  end
end
