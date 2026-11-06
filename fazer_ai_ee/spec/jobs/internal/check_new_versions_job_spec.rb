require 'rails_helper'

# Upstream's version of this spec is written against `ChatwootHub.sync_with_hub`, which the
# fork replaced with a read of its own GitHub releases (#105), so it is superseded by this one
# (see fazer_ai_ee/spec/support/superseded_upstream_examples.rb). With that change the
# enterprise override's `update_plan_info` returns on its first line here; this spec asserts
# what the job does: read the latest release, remember the version, reconcile the plan config.
RSpec.describe Internal::CheckNewVersionsJob do
  subject(:job) { described_class.perform_now }

  let(:reconcile_plan_config_service) { instance_double(Internal::ReconcilePlanConfigService) }
  let(:releases_url) { 'https://api.github.com/repos/fazer-ai/chatwoot/releases/latest' }

  before do
    allow(Internal::ReconcilePlanConfigService).to receive(:new).and_return(reconcile_plan_config_service)
    allow(reconcile_plan_config_service).to receive(:perform)
    allow(Rails.env).to receive(:production?).and_return(true)
    Redis::Alfred.delete(Redis::Alfred::LATEST_CHATWOOT_VERSION)
  end

  it 'remembers the latest released version' do
    stub_request(:get, releases_url).to_return(status: 200, body: { tag_name: 'v1.2.3' }.to_json,
                                               headers: { 'Content-Type' => 'application/json' })

    job

    expect(Redis::Alfred.get(Redis::Alfred::LATEST_CHATWOOT_VERSION)).to eq('1.2.3')
  end

  it 'reconciles the plan config' do
    stub_request(:get, releases_url).to_return(status: 200, body: { tag_name: 'v1.2.3' }.to_json,
                                               headers: { 'Content-Type' => 'application/json' })

    job

    expect(reconcile_plan_config_service).to have_received(:perform)
  end

  # The reconciliation is the half that has to happen even when GitHub is the thing that
  # failed: it reads configuration we already hold, and skipping it because a version
  # lookup timed out would let the plan drift for a day over an unrelated outage.
  it 'still reconciles when the release lookup fails' do
    stub_request(:get, releases_url).to_timeout

    job

    expect(reconcile_plan_config_service).to have_received(:perform)
    expect(Redis::Alfred.get(Redis::Alfred::LATEST_CHATWOOT_VERSION)).to be_nil
  end
end
