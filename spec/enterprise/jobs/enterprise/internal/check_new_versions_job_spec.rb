require 'rails_helper'

RSpec.describe Internal::CheckNewVersionsJob do
  subject(:job) { described_class.perform_now }

  let(:reconsile_premium_config_service) { instance_double(Internal::ReconcilePlanConfigService) }

  before do
    allow(Internal::ReconcilePlanConfigService).to receive(:new).and_return(reconsile_premium_config_service)
    allow(reconsile_premium_config_service).to receive(:perform)

    if ChatwootApp.fazer_ai?
      allow(FazerAiHub).to receive(:sync_subscription).and_return(nil)
      reconcile_service = instance_double(FazerAi::ReconcileSubscriptionService)
      allow(FazerAi::ReconcileSubscriptionService).to receive(:new).and_return(reconcile_service)
      allow(reconcile_service).to receive(:perform)
    end
  end

  it 'updates the plan info' do
    data = { 'version' => '1.2.3', 'plan' => 'enterprise', 'plan_quantity' => 1, 'chatwoot_support_website_token' => '123',
             'chatwoot_support_identifier_hash' => '123', 'chatwoot_support_script_url' => '123' }
    if ChatwootApp.fazer_ai?
      allow(FazerAiHub).to receive(:sync_subscription).and_return(data)
    else
      allow(ChatwootHub).to receive(:sync_with_hub).and_return(data)
    end
    job
    expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').value).to eq 'enterprise'
    expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY').value).to eq 1
    expect(InstallationConfig.find_by(name: 'CHATWOOT_SUPPORT_WEBSITE_TOKEN').value).to eq '123'
    expect(InstallationConfig.find_by(name: 'CHATWOOT_SUPPORT_IDENTIFIER_HASH').value).to eq '123'
    expect(InstallationConfig.find_by(name: 'CHATWOOT_SUPPORT_SCRIPT_URL').value).to eq '123'
  end

  it 'calls Internal::ReconcilePlanConfigService' do
    data = { 'version' => '1.2.3' }
    if ChatwootApp.fazer_ai?
      allow(FazerAiHub).to receive(:sync_subscription).and_return(data)
    else
      allow(ChatwootHub).to receive(:sync_with_hub).and_return(data)
    end
    job
    expect(reconsile_premium_config_service).to have_received(:perform)
  end
end
