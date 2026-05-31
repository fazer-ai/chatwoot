require 'rails_helper'

describe Disparos::CostEstimator do
  describe '#perform' do
    context 'when no price is configured (unknown_price)' do
      subject(:estimator) { described_class.new }

      it 'returns nil for any eligible count' do
        expect(estimator.perform(eligible_count: 10, category: 'marketing')).to be_nil
      end

      it 'returns nil even with a nil category' do
        expect(estimator.perform(eligible_count: 5)).to be_nil
      end

      it 'exposes the default source label' do
        expect(estimator.source).to eq('static_table_beta0')
      end
    end

    context 'when a price table is configured' do
      subject(:estimator) { described_class.new(prices: { 'marketing' => 8, 'utility' => 3 }, source: 'meta_pricelist_2026q2') }

      it 'returns unit_cents * eligible_count for a known category' do
        expect(estimator.perform(eligible_count: 10, category: 'marketing')).to eq(80)
      end

      it 'returns nil (unknown_price) for a category not in the table' do
        expect(estimator.perform(eligible_count: 10, category: 'authentication')).to be_nil
      end

      it 'returns 0 for a known category with zero eligible' do
        expect(estimator.perform(eligible_count: 0, category: 'utility')).to eq(0)
      end

      it 'exposes the configured source label' do
        expect(estimator.source).to eq('meta_pricelist_2026q2')
      end
    end
  end
end
