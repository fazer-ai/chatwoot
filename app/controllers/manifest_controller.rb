class ManifestController < ApplicationController
  PNG_MIME = 'image/png'.freeze
  SVG_MIME = 'image/svg+xml'.freeze

  def show
    config = GlobalConfig.get('INSTALLATION_NAME', 'LOGO_THUMBNAIL', 'BRAND_COLOR')
    installation_name = config['INSTALLATION_NAME'].presence || 'Chatwoot'
    logo = config['LOGO_THUMBNAIL'].presence || '/brand-assets/logo_thumbnail.svg'
    brand_color = config['BRAND_COLOR'].presence || '#1f93ff'
    icon_type = svg?(logo) ? SVG_MIME : PNG_MIME

    expires_in 1.hour, public: true
    render json: {
      name: installation_name,
      short_name: installation_name,
      id: '/',
      start_url: '/',
      display: 'standalone',
      background_color: brand_color,
      theme_color: brand_color,
      icons: [
        { src: logo, sizes: '192x192', type: icon_type, purpose: 'any maskable' },
        { src: logo, sizes: '512x512', type: icon_type, purpose: 'any maskable' }
      ]
    }, content_type: 'application/manifest+json'
  end

  private

  def svg?(url)
    File.extname(URI.parse(url).path).casecmp('.svg').zero?
  rescue URI::InvalidURIError
    false
  end
end
