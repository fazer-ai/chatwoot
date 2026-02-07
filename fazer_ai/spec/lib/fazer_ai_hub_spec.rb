# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAiHub do
  include FazerAi::SubscriptionTokenTestHelper

  after do
    Current.fazer_ai_subscription_data = nil
  end

  def setup_valid_subscription(status: 'active', feature_list: ['kanban'], kanban_limit: 5)
    Current.fazer_ai_subscription_data = nil

    features = feature_list.index_with { {} }
    features['kanban'] = { 'account_limit' => kanban_limit } if feature_list.include?('kanban')

    token = generate_test_subscription_token(
      status: status,
      features: features
    )
    Current.set(fazer_ai_trusted_subscription_update: true) do
      create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: token)
      create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: Time.current.iso8601)
    end
  end

  describe '.installation_identifier' do
    it 'delegates to ChatwootHub' do
      expect(described_class.installation_identifier).to eq(ChatwootHub.installation_identifier)
    end
  end

  describe '.billing_url' do
    it 'returns the billing URL with installation identifier' do
      identifier = described_class.installation_identifier
      expect(described_class.billing_url).to eq("#{described_class::BILLING_URL}?installation_identifier=#{identifier}")
    end
  end

  describe '.subscription_status' do
    context 'when valid token exists and is recently verified' do
      before { setup_valid_subscription(status: 'active') }

      it 'returns the status from token' do
        expect(described_class.subscription_status).to eq('active')
      end
    end

    context 'when no token exists' do
      it 'returns inactive as default' do
        expect(described_class.subscription_status).to eq('inactive')
      end
    end

    context 'when token exists but verification is stale' do
      before do
        token = generate_test_subscription_token(status: 'active')
        Current.set(fazer_ai_trusted_subscription_update: true) do
          create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: token)
          create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: 4.days.ago.iso8601)
        end
      end

      it 'returns inactive' do
        expect(described_class.subscription_status).to eq('inactive')
      end
    end
  end

  describe '.kanban_account_limit' do
    context 'when valid token exists' do
      before { setup_valid_subscription(kanban_limit: 5) }

      it 'returns the limit as integer' do
        expect(described_class.kanban_account_limit).to eq(5)
      end
    end

    context 'when no valid token exists' do
      it 'returns nil' do
        expect(described_class.kanban_account_limit).to be_nil
      end
    end

    context 'when valid token has account_limit 0 (unlimited)' do
      before { setup_valid_subscription(kanban_limit: 0) }

      it 'returns 0' do
        expect(described_class.kanban_account_limit).to eq(0)
      end
    end
  end

  describe '.enabled_features' do
    context 'when valid token exists with features' do
      before { setup_valid_subscription(feature_list: %w[kanban other_feature]) }

      it 'returns the features array' do
        expect(described_class.enabled_features).to contain_exactly('kanban', 'other_feature')
      end
    end

    context 'when no valid token exists' do
      it 'returns empty array' do
        expect(described_class.enabled_features).to eq([])
      end
    end
  end

  describe '.feature_enabled?' do
    before { setup_valid_subscription(feature_list: %w[kanban]) }

    it 'returns true for enabled feature' do
      expect(described_class.feature_enabled?('kanban')).to be(true)
    end

    it 'returns false for disabled feature' do
      expect(described_class.feature_enabled?('other_feature')).to be(false)
    end
  end

  describe '.subscription_active?' do
    it 'returns true for active status with valid token' do
      setup_valid_subscription(status: 'active')
      expect(described_class.subscription_active?).to be(true)
    end

    it 'returns true for past_due status with valid token' do
      setup_valid_subscription(status: 'past_due')
      expect(described_class.subscription_active?).to be(true)
    end

    it 'returns true for trialing status with valid token' do
      setup_valid_subscription(status: 'trialing')
      expect(described_class.subscription_active?).to be(true)
    end

    it 'returns false for inactive status' do
      setup_valid_subscription(status: 'inactive')
      expect(described_class.subscription_active?).to be(false)
    end

    it 'returns false for canceled status' do
      setup_valid_subscription(status: 'canceled')
      expect(described_class.subscription_active?).to be(false)
    end

    it 'returns false when no valid token exists' do
      expect(described_class.subscription_active?).to be(false)
    end
  end

  describe '.subscription_past_due?' do
    it 'returns true when status is past_due' do
      setup_valid_subscription(status: 'past_due')
      expect(described_class.subscription_past_due?).to be(true)
    end

    it 'returns false when status is not past_due' do
      setup_valid_subscription(status: 'active')
      expect(described_class.subscription_past_due?).to be(false)
    end
  end

  describe '.instance_config' do
    it 'returns instance configuration hash' do
      config = described_class.instance_config

      expect(config).to include(
        installation_identifier: described_class.installation_identifier,
        installation_version: Chatwoot.config[:version]
      )
      expect(config).to have_key(:installation_host)
      expect(config).to have_key(:feature_usage)
    end

    it 'includes session_id from FazerAi::Session' do
      session_id = 'test-session-uuid'
      allow(FazerAi::Session).to receive(:session_id).and_return(session_id)

      config = described_class.instance_config

      expect(config[:session_id]).to eq(session_id)
    end
  end

  describe '.feature_usage' do
    it 'returns feature usage with kanban account count' do
      usage = described_class.feature_usage

      expect(usage).to eq({
                            kanban: {
                              account_limit: 0
                            }
                          })
    end

    context 'when accounts have kanban enabled' do
      before do
        setup_valid_subscription
        create(:account).enable_features!('kanban')
        create(:account).enable_features!('kanban')
        create(:account) # no kanban
      end

      it 'returns the correct count' do
        usage = described_class.feature_usage

        expect(usage[:kanban][:account_limit]).to eq(2)
      end
    end
  end

  describe '.kanban_enabled_accounts_count' do
    it 'returns 0 when no accounts have kanban enabled' do
      expect(described_class.kanban_enabled_accounts_count).to eq(0)
    end

    context 'when accounts have kanban enabled' do
      before do
        setup_valid_subscription
        create(:account).enable_features!('kanban')
        create(:account).enable_features!('kanban')
        create(:account) # no kanban
      end

      it 'returns the count of accounts with kanban enabled' do
        expect(described_class.kanban_enabled_accounts_count).to eq(2)
      end
    end
  end

  describe '.sync_subscription' do
    let(:hub_response) do
      {
        'version' => '4.0.0',
        'subscription_token' => generate_test_subscription_token
      }
    end

    context 'when request is successful' do
      before do
        stub_request(:post, described_class::PING_URL)
          .to_return(
            status: 200,
            body: hub_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns parsed response' do
        result = described_class.sync_subscription

        expect(result).to include('version' => '4.0.0')
        expect(result).to have_key('subscription_token')
      end
    end

    context 'when request fails' do
      before do
        stub_request(:post, described_class::PING_URL)
          .to_return(status: 500)
      end

      it 'returns nil' do
        expect(described_class.sync_subscription).to be_nil
      end
    end

    context 'when request returns 403 (no subscription)' do
      before do
        stub_request(:post, described_class::PING_URL)
          .to_return(status: 403, body: { error: 'No subscription' }.to_json)
      end

      it 'returns inactive hash' do
        expect(described_class.sync_subscription).to eq({ 'inactive' => true })
      end
    end

    context 'when request raises error' do
      before do
        stub_request(:post, described_class::PING_URL)
          .to_raise(StandardError.new('Connection failed'))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns nil and logs error' do
        expect(described_class.sync_subscription).to be_nil
        expect(Rails.logger).to have_received(:error).with('[fazer.ai] Hub sync error: Connection failed')
      end
    end
  end

  describe '.synced?' do
    it 'returns true when token exists and was recently verified' do
      setup_valid_subscription
      expect(described_class.synced?).to be(true)
    end

    it 'returns false when no token exists' do
      expect(described_class.synced?).to be(false)
    end

    it 'returns false when verification is stale' do
      token = generate_test_subscription_token
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: token)
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: 4.days.ago.iso8601)
      end
      expect(described_class.synced?).to be(false)
    end
  end

  describe '.never_synced?' do
    it 'returns true when no verification timestamp exists' do
      expect(described_class.never_synced?).to be(true)
    end

    it 'returns false when verification timestamp exists' do
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: Time.current.iso8601)
      end
      expect(described_class.never_synced?).to be(false)
    end

    it 'returns false even when verification is stale' do
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: 4.days.ago.iso8601)
      end
      expect(described_class.never_synced?).to be(false)
    end
  end

  describe '.out_of_sync?' do
    it 'returns false when no sync error exists' do
      expect(described_class.out_of_sync?).to be(false)
    end

    it 'returns true when sync error config exists' do
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_SYNC_ERROR', value: Time.current.iso8601)
      end
      expect(described_class.out_of_sync?).to be(true)
    end
  end

  describe '.sync_error_at' do
    it 'returns nil when no sync error exists' do
      expect(described_class.sync_error_at).to be_nil
    end

    it 'returns parsed time when sync error exists' do
      error_time = 2.hours.ago
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_SYNC_ERROR', value: error_time.iso8601)
      end
      expect(described_class.sync_error_at).to be_within(1.second).of(error_time)
    end
  end

  describe '.last_synced_at' do
    it 'returns nil when no verification exists' do
      expect(described_class.last_synced_at).to be_nil
    end

    it 'returns parsed time when verification exists' do
      verified_time = 1.hour.ago
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: verified_time.iso8601)
      end
      expect(described_class.last_synced_at).to be_within(1.second).of(verified_time)
    end
  end

  describe '.last_known_subscription_status' do
    it 'returns nil when no token exists' do
      expect(described_class.last_known_subscription_status).to be_nil
    end

    it 'returns status from token without verifying signature' do
      token = generate_test_subscription_token(status: 'active')
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: token)
      end
      expect(described_class.last_known_subscription_status).to eq('active')
    end
  end

  describe 'out of sync behavior' do
    context 'when out of sync with existing token' do
      before do
        token = generate_test_subscription_token(status: 'active')
        Current.set(fazer_ai_trusted_subscription_update: true) do
          create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: token)
          create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: 1.hour.ago.iso8601)
          create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_SYNC_ERROR', value: 30.minutes.ago.iso8601)
        end
      end

      it 'returns last known status for subscription_status' do
        expect(described_class.subscription_status).to eq('active')
      end

      it 'returns true for subscription_active?' do
        expect(described_class.subscription_active?).to be(true)
      end
    end

    context 'when out of sync without token' do
      before do
        Current.set(fazer_ai_trusted_subscription_update: true) do
          create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_SYNC_ERROR', value: 30.minutes.ago.iso8601)
        end
      end

      it 'returns inactive for subscription_status' do
        expect(described_class.subscription_status).to eq('inactive')
      end

      it 'returns false for subscription_active?' do
        expect(described_class.subscription_active?).to be(false)
      end
    end
  end

  describe '.subscription_verified_recently?' do
    it 'returns true when verified within token validity window' do
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: 1.hour.ago.iso8601)
      end
      expect(described_class.subscription_verified_recently?).to be(true)
    end

    it 'returns false when verification is stale' do
      Current.set(fazer_ai_trusted_subscription_update: true) do
        create(:installation_config, name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT', value: 4.days.ago.iso8601)
      end
      expect(described_class.subscription_verified_recently?).to be(false)
    end

    it 'returns false when no verification timestamp exists' do
      expect(described_class.subscription_verified_recently?).to be(false)
    end
  end
end
