require 'rails_helper'

# This spec was red for at least a release, and nothing in this repo ran it:
# `run_foss_spec.yml` deletes `enterprise` and `spec/enterprise` before the suite.
#
# Why it was red, read off the history rather than guessed: it was written against
# `ChatwootHub.sync_with_hub`, and `dbb41df67e` (fork PR #105) replaced that call with a
# read of our own GitHub releases, taking `@instance_info` with it. The enterprise
# override still reads that ivar and was last touched by `390cd756e8`, which came from
# upstream, so nothing adapted it on this side.
#
# What follows from that is only this: `update_plan_info` returns on its first line here
# and writes no installation config. Whether that is intended, because Pro sets those
# values somewhere else, or an unnoticed consequence of #105, is not something this repo
# can answer, and this spec deliberately asserts neither. It asserts what the job does:
# read the latest release, remember the version, and reconcile the plan config.
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
