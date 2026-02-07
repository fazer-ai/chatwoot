# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::ReconcileSubscriptionService do
  subject(:service) { described_class.new }

  before do
    allow(ChatwootApp).to receive(:fazer_ai?).and_return(true)
  end

  describe '#perform' do
    context 'when fazer_ai is not enabled' do
      before do
        allow(ChatwootApp).to receive(:fazer_ai?).and_return(false)
      end

      it 'does nothing' do
        expect(FazerAiHub).not_to receive(:subscription_active?)
        service.perform
      end
    end

    context 'when subscription is not active' do
      let!(:account1) { create(:account) }
      let!(:account2) { create(:account) }

      before do
        allow(FazerAiHub).to receive(:subscription_active?).and_return(false)
        account1.enable_features!('kanban')
        account2.enable_features!('kanban')
      end

      it 'does not reconcile features' do
        service.perform

        expect(account1.reload.feature_enabled?('kanban')).to be(true)
        expect(account2.reload.feature_enabled?('kanban')).to be(true)
      end
    end

    context 'when subscription is active and kanban feature is enabled' do
      before do
        allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
      end

      it 'does not touch accounts when limit is 0 (unlimited)' do
        stub_fazer_ai_hub(kanban_limit: 100)
        account1 = create(:account)
        account2 = create(:account)
        account3 = create(:account)
        account1.enable_features!('kanban')
        account2.enable_features!('kanban')
        account3.enable_features!('kanban')

        # Limit becomes 0 (unlimited) - all accounts keep their flag
        stub_fazer_ai_hub(kanban_limit: 0)
        service.perform

        expect(account1.reload.feature_enabled?('kanban')).to be(true)
        expect(account2.reload.feature_enabled?('kanban')).to be(true)
        expect(account3.reload.feature_enabled?('kanban')).to be(true)
      end

      it 'does not touch accounts when limit is nil (feature not available)' do
        stub_fazer_ai_hub(kanban_limit: 100)
        account1 = create(:account)
        account2 = create(:account)
        account1.enable_features!('kanban')
        account2.enable_features!('kanban')

        allow(FazerAiHub).to receive(:kanban_account_limit).and_return(nil)
        service.perform

        expect(account1.reload.feature_enabled?('kanban')).to be(true)
        expect(account2.reload.feature_enabled?('kanban')).to be(true)
      end

      it 'disables feature for accounts with highest IDs when limit exceeded' do
        stub_fazer_ai_hub(kanban_limit: 100)
        account1 = create(:account)
        account2 = create(:account)
        account3 = create(:account)
        account1.enable_features!('kanban')
        account2.enable_features!('kanban')
        account3.enable_features!('kanban')

        stub_fazer_ai_hub(kanban_limit: 2)
        service.perform

        expect(account1.reload.feature_enabled?('kanban')).to be(true)
        expect(account2.reload.feature_enabled?('kanban')).to be(true)
        expect(account3.reload.feature_enabled?('kanban')).to be(false)
      end

      it 'does not disable accounts when within limit' do
        stub_fazer_ai_hub(kanban_limit: 5)
        account1 = create(:account)
        account2 = create(:account)
        account1.enable_features!('kanban')
        account2.enable_features!('kanban')

        service.perform

        expect(account1.reload.feature_enabled?('kanban')).to be(true)
        expect(account2.reload.feature_enabled?('kanban')).to be(true)
      end
    end

    context 'when kanban feature is not enabled in subscription' do
      before do
        allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
        allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(false)
      end

      it 'does not reconcile kanban limits' do
        expect(FazerAiHub).not_to receive(:kanban_account_limit)
        service.perform
      end
    end
  end
end
