require 'rails_helper'

RSpec.describe Internal::CheckNewVersionsJob do
  subject(:job) { described_class.perform_now }

  before do
    if ChatwootApp.fazer_ai?
      allow(ChatwootHub).to receive(:sync_with_hub).and_return(nil)
      allow(FazerAiHub).to receive(:sync_subscription).and_return(nil)
      reconcile_service = instance_double(FazerAi::ReconcileSubscriptionService)
      allow(FazerAi::ReconcileSubscriptionService).to receive(:new).and_return(reconcile_service)
      allow(reconcile_service).to receive(:perform)
    end
  end

  it 'updates the latest chatwoot version in redis' do
    data = { 'version' => '1.2.3' }
    allow(ChatwootHub).to receive(:sync_with_hub).and_return(data)
    allow(FazerAiHub).to receive(:sync_subscription).and_return(data) if ChatwootApp.fazer_ai?
    job
    expect(Redis::Alfred.get(Redis::Alfred::LATEST_CHATWOOT_VERSION)).to eq data['version']
  end
end
