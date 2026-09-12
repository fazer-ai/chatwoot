class Internal::AccountAnalysis::WebsiteScraperService
  def initialize(domain)
    @domain = domain
  end

  def perform
    return nil if @domain.blank?

    Rails.logger.info("Scraping website: #{external_link}")

    begin
      # Whatever address the account put on its own record, so the wait is on a site
      # nobody here controls and the ceiling is the only thing bounding it.
      response = HTTParty.get(external_link, follow_redirects: true, timeout: 15, max_retries: 0)
      response.to_s
    rescue StandardError => e
      Rails.logger.error("Error scraping website for domain #{@domain}: #{e.message}")
      nil
    end
  end

  private

  def external_link
    sanitize_url(@domain)
  end

  def sanitize_url(domain)
    url = domain
    url = "https://#{domain}" unless domain.start_with?('http://', 'https://')
    Rails.logger.info("Sanitized URL: #{url}")
    url
  end
end
