# frozen_string_literal: true

module FazerAiTestHelpers
  def stub_fazer_ai_hub(synced: true, kanban_limit: 100, subscription_active: true, feature_enabled: true)
    allow(FazerAiHub).to receive(:synced?).and_return(synced)
    allow(FazerAiHub).to receive(:kanban_account_limit).and_return(kanban_limit)
    allow(FazerAiHub).to receive(:subscription_active?).and_return(subscription_active)
    allow(FazerAiHub).to receive(:feature_enabled?).and_return(feature_enabled)
  end

  def unstub_fazer_ai_hub
    allow(FazerAiHub).to receive(:synced?).and_call_original
    allow(FazerAiHub).to receive(:kanban_account_limit).and_call_original
    allow(FazerAiHub).to receive(:subscription_active?).and_call_original
    allow(FazerAiHub).to receive(:feature_enabled?).and_call_original
  end

  def stub_fazer_ai_hub_request(response_body: {})
    stub_request(:post, FazerAiHub::PING_URL)
      .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end
end

RSpec.configure do |config|
  config.include FazerAiTestHelpers

  config.before do |example|
    if example.metadata[:file_path]&.include?('fazer_ai/spec/')
      stub_request(:post, FazerAiHub::PING_URL)
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      # Also stub ChatwootHub ping called when enabling kanban feature
      stub_request(:post, "#{ChatwootHub::BASE_URL}/ping")
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    end

    if example.metadata[:file_path]&.include?('fazer_ai/spec/') &&
       !example.metadata[:file_path]&.include?('concerns/account_spec') &&
       !example.metadata[:file_path]&.include?('lib/fazer_ai_hub_spec')
      allow(FazerAiHub).to receive(:synced?).and_return(true)
      allow(FazerAiHub).to receive(:kanban_account_limit).and_return(100)
      allow(FazerAiHub).to receive(:subscription_active?).and_return(true)
      allow(FazerAiHub).to receive(:feature_enabled?).and_return(true)
    end
  end
end
