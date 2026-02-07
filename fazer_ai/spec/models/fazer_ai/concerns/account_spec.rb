# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Concerns::Account do
  let(:account) { create(:account) }

  before do
    allow(ChatwootApp).to receive(:fazer_ai?).and_return(true)
  end

  describe '#kanban_feature_enabled?' do
    context 'when feature flag is disabled' do
      it 'returns false' do
        expect(account.kanban_feature_enabled?).to be(false)
      end
    end

    context 'when feature flag is enabled' do
      before do
        allow(FazerAiHub).to receive(:synced?).and_return(true)
        allow(FazerAiHub).to receive(:kanban_account_limit).and_return(100)
        account.enable_features!('kanban')
      end

      context 'when subscription is active and feature is enabled in subscription' do
        before do
          allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
          allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(true)
        end

        it 'returns true' do
          expect(account.kanban_feature_enabled?).to be(true)
        end
      end

      context 'when subscription is active and account limit is 0 (unlimited)' do
        before do
          allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
          allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(true)
          allow(FazerAiHub).to receive(:kanban_account_limit).and_return(0)
        end

        it 'returns true (unlimited access)' do
          expect(account.kanban_feature_enabled?).to be(true)
        end
      end

      context 'when subscription is active but account limit is nil (not available)' do
        before do
          allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
          allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(true)
          allow(FazerAiHub).to receive(:kanban_account_limit).and_return(nil)
        end

        it 'returns false' do
          expect(account.kanban_feature_enabled?).to be(false)
        end
      end

      context 'when subscription is not active' do
        before do
          allow(FazerAiHub).to receive(:subscription_active?).and_return(false)
          allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(true)
        end

        it 'returns false' do
          expect(account.kanban_feature_enabled?).to be(false)
        end
      end

      context 'when feature is not enabled in subscription' do
        before do
          allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
          allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(false)
        end

        it 'returns false' do
          expect(account.kanban_feature_enabled?).to be(false)
        end
      end
    end
  end

  describe '#fazer_ai_subscription_feature_accessible?' do
    context 'when subscription is active and feature is enabled' do
      before do
        allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
        allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(true)
      end

      it 'returns true' do
        expect(account.fazer_ai_subscription_feature_accessible?('kanban')).to be(true)
      end
    end

    context 'when subscription is not active' do
      before do
        allow(FazerAiHub).to receive(:subscription_active?).and_return(false)
      end

      it 'returns false' do
        expect(account.fazer_ai_subscription_feature_accessible?('kanban')).to be(false)
      end
    end

    context 'when feature is not enabled in subscription' do
      before do
        allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
        allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(false)
      end

      it 'returns false' do
        expect(account.fazer_ai_subscription_feature_accessible?('kanban')).to be(false)
      end
    end
  end

  describe '.fazer_ai_feature?' do
    it 'returns true for features marked as fazer_ai' do
      expect(described_class.fazer_ai_feature?('kanban')).to be(true)
    end

    it 'returns false for features not marked as fazer_ai' do
      expect(described_class.fazer_ai_feature?('channel_email')).to be(false)
    end

    it 'returns false for non-existent features' do
      expect(described_class.fazer_ai_feature?('non_existent_feature')).to be(false)
    end
  end

  describe 'fazer_ai feature validation' do
    describe 'sync and validation' do
      before do
        allow(Internal::CheckNewVersionsJob).to receive(:perform_now)
        allow(Internal::CheckNewVersionsJob).to receive(:perform_later)
      end

      context 'when enabling kanban feature' do
        before do
          allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(true)
          allow(FazerAiHub).to receive(:kanban_account_limit).and_return(100)
        end

        it 'forces a sync before validation' do
          account.enable_features!('kanban')

          expect(Internal::CheckNewVersionsJob).to have_received(:perform_now)
        end

        it 'allows enabling fazer_ai features when within limit' do
          expect { account.enable_features!('kanban') }.not_to raise_error
          expect(account.feature_enabled?('kanban')).to be(true)
        end
      end
    end

    describe 'kanban limit validation' do
      before do
        allow(Internal::CheckNewVersionsJob).to receive(:perform_now)
        allow(Internal::CheckNewVersionsJob).to receive(:perform_later)
        allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(true)
      end

      context 'when limit is nil (feature not available)' do
        before do
          allow(FazerAiHub).to receive(:kanban_account_limit).and_return(nil)
        end

        it 'blocks enabling the feature' do
          expect { account.enable_features!('kanban') }.to raise_error(
            ActiveRecord::RecordInvalid,
            /Kanban feature is not available/
          )
        end
      end

      context 'when limit is 0 (unlimited)' do
        before do
          allow(FazerAiHub).to receive(:kanban_account_limit).and_return(0)
        end

        it 'allows enabling the feature without restriction' do
          expect { account.enable_features!('kanban') }.not_to raise_error
          expect(account.feature_enabled?('kanban')).to be(true)
        end
      end

      context 'when limit is reached' do
        let!(:existing_account1) { create(:account) }
        let!(:existing_account2) { create(:account) }

        before do
          allow(FazerAiHub).to receive(:kanban_account_limit).and_return(2)
          existing_account1.enable_features!('kanban')
          existing_account2.enable_features!('kanban')
        end

        it 'prevents enabling the feature on new account' do
          new_account = create(:account)
          new_account.enable_features('kanban')

          expect(new_account.save).to be(false)
          expect(new_account.errors[:base]).to include(
            I18n.t('errors.fazer_ai.kanban_account_limit_reached', limit: 2)
          )
        end

        it 'allows re-saving existing account with feature already enabled' do
          existing_account1.name = 'Updated Name'
          expect(existing_account1.save).to be(true)
        end
      end

      context 'when within limit' do
        let!(:existing_account) { create(:account) }

        before do
          allow(FazerAiHub).to receive(:kanban_account_limit).and_return(5)
          existing_account.enable_features!('kanban')
        end

        it 'allows enabling the feature' do
          expect { account.enable_features!('kanban') }.not_to raise_error
          expect(account.feature_enabled?('kanban')).to be(true)
        end
      end
    end
  end

  describe '#sync_fazer_ai_feature_usage' do
    before do
      allow(FazerAiHub).to receive(:kanban_account_limit).and_return(100)
      allow(FazerAiHub).to receive(:feature_enabled?).with('kanban').and_return(true)
      allow(Internal::CheckNewVersionsJob).to receive(:perform_now)
      allow(Internal::CheckNewVersionsJob).to receive(:perform_later)
    end

    it 'runs CheckNewVersionsJob during validation when kanban feature is enabled' do
      account.enable_features!('kanban')

      expect(Internal::CheckNewVersionsJob).to have_received(:perform_now).once
    end

    it 'enqueues CheckNewVersionsJob after commit when kanban feature is enabled' do
      account.enable_features!('kanban')

      expect(Internal::CheckNewVersionsJob).to have_received(:perform_later).once
    end

    it 'enqueues CheckNewVersionsJob when kanban feature is disabled' do
      account.enable_features!('kanban')

      expect(Internal::CheckNewVersionsJob).to receive(:perform_later).once
      account.disable_features!('kanban')
    end

    it 'does not sync when other features change' do
      allow(Internal::CheckNewVersionsJob).to receive(:perform_now)
      allow(Internal::CheckNewVersionsJob).to receive(:perform_later)

      account.enable_features!('channel_email')

      expect(Internal::CheckNewVersionsJob).not_to have_received(:perform_now)
      expect(Internal::CheckNewVersionsJob).not_to have_received(:perform_later)
    end
  end
end
