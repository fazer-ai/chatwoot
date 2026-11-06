# The wait and retry ceilings the fork puts on Enterprise's outbound HTTP calls. Upstream calls
# HTTParty with no timeout (Net::HTTP waits 60s per read) and Net::HTTP retries an idempotent
# request once, so a slow provider holds a Puma thread, and sometimes a row lock, for minutes.
#
# Each listed method runs inside a ceiling scope, and HTTParty calls made inside it get the
# ceiling as default options. Options the call passes itself still win, and outside a listed
# method HTTParty behaves exactly as before: this is not a global default.
#
# fazer_ai_ee/spec/lib/request_ceilings_spec.rb fails when a new HTTParty call shows up in
# enterprise/ outside every listed method, and checks each listed method end to end.
module FazerAiEe::RequestCeilings
  SCOPE_KEY = :fazer_ai_ee_request_ceiling
  OFFSITE = { timeout: 15, max_retries: 0 }.freeze # a site nobody here controls
  SERVICE = { timeout: 10, max_retries: 0 }.freeze # a provider API answering on its own state

  # `self.` marks a class method.
  def self.ceilings
    graph = Whatsapp::GraphRequestOptions::GRAPH_REQUEST_OPTIONS
    {
      # A chat completion: the thinking time before the first byte is the point of the call, and
      # a repeat is a second answer and a second bill.
      'Article' => { generate_article_search_terms: { timeout: 120, max_retries: 0 } },
      # `crawl` only registers the job; `scrape` fetches the page before answering.
      'Captain::Tools::FirecrawlService' => { perform: { timeout: 20, max_retries: 0 }, scrape: { timeout: 60, max_retries: 0 } },
      'Captain::ToolsManifest::GithubSource' => { get: { max_retries: 0 } }, # keeps its own timeout
      'Cloudflare::CheckCustomHostnameService' => { perform: SERVICE },
      'Cloudflare::CreateCustomHostnameService' => { create_hostname: SERVICE },
      'Companies::EnrichmentService' => { fetch_brand: { max_retries: 0 } }, # keeps its own timeout
      'Enterprise::ClearbitLookupService' => { 'self.perform_request': SERVICE },
      'WebsiteBrandingService' => { fetch_brand: SERVICE },
      'Internal::AccountAnalysis::DiscordNotifierService' => { notify_flagged_account: SERVICE },
      'Internal::AccountAnalysis::WebsiteScraperService' => { perform: OFFSITE },
      'Internal::Accounts::MarketingConversionTrackingService' => { perform: SERVICE },
      'PageCrawlerService' => { initialize: OFFSITE },
      # WhatsApp calling: Meta slow to answer would hold the request and the Call row lock.
      'Whatsapp::Providers::WhatsappCloudService' => {
        send_call_permission_request: graph, initiate_call: graph, update_calling_status: graph, call_api: graph
      }
    }
  end

  module HTTPartyScope
    %i[get post put patch delete head options].each do |verb|
      define_method(verb) do |path, options = {}, &block|
        super(path, FazerAiEe::RequestCeilings.apply(options), &block)
      end
    end
  end

  def self.within(ceiling)
    previous = ActiveSupport::IsolatedExecutionState[SCOPE_KEY]
    ActiveSupport::IsolatedExecutionState[SCOPE_KEY] = ceiling
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[SCOPE_KEY] = previous
  end

  def self.apply(options)
    ceiling = ActiveSupport::IsolatedExecutionState[SCOPE_KEY]
    ceiling ? ceiling.merge(options.to_h) : options
  end

  def self.install!
    HTTParty.singleton_class.prepend(HTTPartyScope) unless HTTParty.singleton_class <= HTTPartyScope

    ceilings.each do |class_name, methods|
      klass = class_name.constantize
      instance_methods, class_methods = methods.partition { |name, _| !name.to_s.start_with?('self.') }
      klass.prepend(scope_for(klass, instance_methods))
      klass.singleton_class.prepend(scope_for(klass.singleton_class, class_methods))
    end
  end

  def self.scope_for(target, methods)
    Module.new.tap do |scope|
      methods.each do |name, ceiling|
        method_name = name.to_s.delete_prefix('self.').to_sym
        raise ArgumentError, "#{target}##{method_name} does not exist" unless method_defined_anywhere?(target, method_name)

        scope.define_method(method_name) do |*args, **kwargs, &block|
          FazerAiEe::RequestCeilings.within(ceiling) { super(*args, **kwargs, &block) }
        end
        scope.send(:private, method_name) if target.private_method_defined?(method_name)
      end
    end
  end

  def self.method_defined_anywhere?(target, name)
    target.method_defined?(name) || target.private_method_defined?(name)
  end
end
