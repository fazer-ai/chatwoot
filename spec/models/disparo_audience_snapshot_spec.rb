require 'rails_helper'

RSpec.describe DisparoAudienceSnapshot do
  describe 'associations' do
    it { is_expected.to belong_to(:disparo) }
  end

  describe 'aggregate snapshot' do
    it 'persists with jsonb and array aggregate defaults' do
      snapshot = create(:disparo_audience_snapshot)
      expect(snapshot.filter_dsl).to eq({})
      expect(snapshot.inbox_ids).to eq([])
      expect(snapshot.total_eligible).to eq(0)
      expect(snapshot.by_skip_reason).to eq({})
      expect(snapshot.by_inbox).to eq({})
      expect(snapshot.estimated_cost_cents).to be_nil
      # GAP B: config_fingerprint is nullable; the dry-run service fills it.
      expect(snapshot.config_fingerprint).to be_nil
    end

    it 'persists a config_fingerprint when set' do
      snapshot = create(:disparo_audience_snapshot, config_fingerprint: 'abc123')
      expect(snapshot.reload.config_fingerprint).to eq('abc123')
    end
  end
end
