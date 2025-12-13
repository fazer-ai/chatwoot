# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Internal::CheckNewVersionsJob do
  include FazerAi::SubscriptionTokenTestHelper

  subject(:job) { Internal::CheckNewVersionsJob.new }

  before do
    allow(ChatwootApp).to receive(:fazer_ai?).and_return(true)
    Redis::Alfred.delete(Redis::Alfred::LATEST_CHATWOOT_VERSION)
  end

  describe '#perform' do
    context 'when hub returns successful response with valid token' do
      before do
        hub_response = generate_hub_response_with_token(
          status: 'active',
          features: { 'chatwoot_kanban' => { 'account_limit' => 5 } },
          version: '4.0.0'
        )

        stub_request(:post, FazerAiHub::PING_URL)
          .to_return(
            status: 200,
            body: hub_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'updates the latest version in redis' do
        job.perform

        expect(Redis::Alfred.get(Redis::Alfred::LATEST_CHATWOOT_VERSION)).to eq('4.0.0')
      end

      it 'stores the subscription token' do
        job.perform

        config = InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_TOKEN')
        expect(config).to be_present
        expect(config.value).to be_present
      end

      it 'updates subscription verified_at timestamp' do
        job.perform

        config = InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_VERIFIED_AT')
        expect(config).to be_present
        expect(Time.zone.parse(config.value)).to be_within(1.minute).of(Time.current)
      end

      it 'calls reconciliation service' do
        reconcile_service = instance_double(FazerAi::ReconcileSubscriptionService)
        allow(FazerAi::ReconcileSubscriptionService).to receive(:new).and_return(reconcile_service)
        allow(reconcile_service).to receive(:perform)

        job.perform

        expect(reconcile_service).to have_received(:perform)
      end
    end

    context 'when hub returns response without subscription_token' do
      before do
        stub_request(:post, FazerAiHub::PING_URL)
          .to_return(
            status: 200,
            body: { 'version' => '4.0.0' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'updates redis version' do
        job.perform

        expect(Redis::Alfred.get(Redis::Alfred::LATEST_CHATWOOT_VERSION)).to eq('4.0.0')
      end

      it 'does not create subscription configs' do
        job.perform

        expect(InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_TOKEN')).to be_nil
      end
    end

    context 'when hub returns response with invalid token' do
      before do
        stub_request(:post, FazerAiHub::PING_URL)
          .to_return(
            status: 200,
            body: { 'version' => '4.0.0', 'subscription_token' => 'invalid.token.here' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'does not create subscription configs' do
        job.perform

        expect(InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_TOKEN')).to be_nil
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/\[fazer\.ai\].*subscription token/i).at_least(:once)
        job.perform
      end
    end

    context 'when hub request fails' do
      before do
        stub_request(:post, FazerAiHub::PING_URL)
          .to_return(status: 500)
      end

      it 'does not update redis' do
        job.perform

        expect(Redis::Alfred.get(Redis::Alfred::LATEST_CHATWOOT_VERSION)).to be_nil
      end

      it 'does not create subscription configs' do
        job.perform

        expect(InstallationConfig.find_by(name: 'FAZER_AI_SUBSCRIPTION_TOKEN')).to be_nil
      end
    end
  end
end
