require 'rails_helper'
require 'prism'

# rubocop:disable RSpec/DescribeClass -- the subject is FazerAiEe::RequestCeilings, read through
# the HTTParty options that reach the wire for each Enterprise call it covers.
RSpec.describe 'the ceilings on Enterprise HTTP calls' do
  # What HTTParty::Basement, the layer below the scope, was asked to send.
  let(:sent) { [] }
  let(:response) do
    instance_double(HTTParty::Response, success?: true, code: 200, body: '{}', to_s: '',
                                        parsed_response: { 'result' => nil, 'errors' => [] })
  end

  before do
    %i[get post].each do |verb|
      allow(HTTParty::Basement).to receive(verb) do |path, options = {}, &_block|
        sent << [path, options]
        response
      end
    end
  end

  def options_sent
    expect(sent).not_to be_empty
    sent.map(&:last)
  end

  def run_through(&)
    yield
  rescue StandardError
    # Only what was sent matters here; the fake response is not a valid answer for every caller.
    nil
  end

  # A fence, not a checklist: every HTTParty call in upstream's Enterprise tree sits inside a
  # method the fork puts a ceiling on. An upstream merge that adds a call fails here.
  it 'covers every HTTParty call in enterprise/' do
    covered = FazerAiEe::RequestCeilings.ceilings.values.flat_map { |methods| methods.keys.map { |name| name.to_s.delete_prefix('self.').to_sym } }
    bare = Rails.root.glob('enterprise/**/*.rb').flat_map do |path|
      stack = [[Prism.parse(path.read).value, nil]]
      found = []
      until stack.empty?
        node, method = stack.pop
        method = node.name if node.is_a?(Prism::DefNode)
        stack.concat(node.compact_child_nodes.map { |child| [child, method] })
        next unless node.is_a?(Prism::CallNode) && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :HTTParty

        found << "#{path.relative_path_from(Rails.root)}:#{node.location.start_line} (#{method})" unless covered.include?(method)
      end
      found
    end

    expect(bare).to be_empty
  end

  it 'leaves HTTParty untouched outside a covered method' do
    HTTParty.get('https://example.com/plain', headers: { 'X' => '1' })

    expect(sent.sole.last).to eq(headers: { 'X' => '1' })
  end

  it 'lets the options a call passes itself win over the ceiling' do
    FazerAiEe::RequestCeilings.within(timeout: 10, max_retries: 0) { HTTParty.get('https://example.com', timeout: 3) }

    expect(sent.sole.last).to eq(timeout: 3, max_retries: 0)
  end

  it 'gives the article search terms completion the long ceiling' do
    article = create(:article)
    allow(article).to receive_messages(openai_api_key: 'key', openai_api_url: 'https://api.openai.com/v1/chat/completions')

    run_through { article.generate_article_search_terms }

    expect(options_sent).to all(include(timeout: 120, max_retries: 0))
  end

  it 'waits longer on a Firecrawl scrape than on registering a crawl' do
    create(:installation_config, name: 'CAPTAIN_FIRECRAWL_API_KEY', value: 'key')
    service = Captain::Tools::FirecrawlService.new

    run_through { service.perform('https://example.com', 'https://hooks.example.com') }
    run_through { service.scrape('https://example.com') }

    expect(options_sent).to match([include(timeout: 20, max_retries: 0), include(timeout: 60, max_retries: 0)])
  end

  it 'keeps the GitHub manifest timeout and stops the retry' do
    source = Captain::ToolsManifest::GithubSource.allocate

    run_through { source.send(:get, 'https://raw.githubusercontent.com/o/r/main/tools.json') }

    expect(options_sent.sole).to include(timeout: Captain::ToolsManifest::GithubSource::REQUEST_TIMEOUT, max_retries: 0)
  end

  it 'puts the service ceiling on both Cloudflare hostname calls' do
    create(:installation_config, name: 'CLOUDFLARE_API_KEY', value: 'token')
    create(:installation_config, name: 'CLOUDFLARE_ZONE_ID', value: 'zone')
    portal = create(:portal, custom_domain: 'help.example.com')

    run_through { Cloudflare::CheckCustomHostnameService.new(portal: portal).perform }
    run_through { Cloudflare::CreateCustomHostnameService.new(portal: portal).perform }

    expect(options_sent).to match([include(timeout: 10, max_retries: 0), include(timeout: 10, max_retries: 0)])
  end

  it 'keeps the company enrichment timeout and stops the retry' do
    company = create(:company, domain: 'example.com')

    run_through { Companies::EnrichmentService.new(company).send(:fetch_brand) }

    expect(options_sent.sole).to include(timeout: (Companies::EnrichmentService::TIMEOUT_MS / 1000) + 5, max_retries: 0)
  end

  it 'puts the service ceiling on the Clearbit lookup' do
    run_through { Enterprise::ClearbitLookupService.perform_request('someone@example.com') }

    expect(options_sent.sole).to include(timeout: 10, max_retries: 0)
  end

  it 'puts the service ceiling on the Context.dev branding lookup' do
    create(:installation_config, name: 'CONTEXT_DEV_API_KEY', value: 'key')

    run_through { WebsiteBrandingService.new('someone@example.com').perform }

    expect(options_sent.sole).to include(timeout: 10, max_retries: 0)
  end

  it 'puts the service ceiling on the Discord notification of a flagged account' do
    service = Internal::AccountAnalysis::DiscordNotifierService.new
    allow(service).to receive(:webhook_url).and_return('https://discord.example.com/hook')

    run_through { service.notify_flagged_account(create(:account)) }

    expect(options_sent.sole).to include(timeout: 10, max_retries: 0)
  end

  it 'puts the off-site ceiling on the account website scrape' do
    run_through { Internal::AccountAnalysis::WebsiteScraperService.new('example.com').perform }

    expect(options_sent.sole).to include(timeout: 15, max_retries: 0)
  end

  it 'puts the service ceiling on the marketing conversion upload' do
    allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
    service = Internal::Accounts::MarketingConversionTrackingService.new(account: create(:account), event_name: 'cloud_signup')
    allow(service).to receive_messages(click_attributes: { 'gclid' => 'x' }, access_token: 'token',
                                       destination_payload: {}, conversion_payload: {})

    run_through { service.perform }

    expect(options_sent.sole).to include(timeout: 10, max_retries: 0)
  end

  it 'puts the off-site ceiling on the page crawler fetch' do
    run_through { PageCrawlerService.new('https://example.com') }

    expect(options_sent.sole).to include(timeout: 15, max_retries: 0)
  end

  it 'puts the Graph ceiling on every WhatsApp calling request' do
    channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    service = Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel)

    run_through { service.send_call_permission_request('15550001111') }
    run_through { service.initiate_call('15550001111', 'sdp') }
    run_through { service.update_calling_status('enabled') }
    run_through { service.send(:call_api, 'accept', { call_id: 'wacid', action: 'accept' }) }

    expect(options_sent.size).to eq(4)
    expect(options_sent).to all(include(Whatsapp::GraphRequestOptions::GRAPH_REQUEST_OPTIONS))
  end
end
# rubocop:enable RSpec/DescribeClass
