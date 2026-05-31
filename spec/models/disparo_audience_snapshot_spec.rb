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
    end
  end
end
