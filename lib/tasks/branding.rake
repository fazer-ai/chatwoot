# NOTE: See https://github.com/fazer-ai/chatwoot/blob/main/CUSTOM_BRANDING.md for more details.
module BrandingTaskHelper
  CONFIGURABLE_ITEMS = {
    # The installation wide name that would be used in the dashboard, title etc.
    'INSTALLATION_NAME' => 'Chatwoot',
    # The thumbnail that would be used for favicon (512px X 512px)
    'LOGO_THUMBNAIL' => '/brand-assets/logo_thumbnail.svg',
    # The logo that would be used on the dashboard, login page etc.
    'LOGO' => '/brand-assets/logo.svg',
    # The logo that would be used on the dashboard, login page etc. for dark mode
    'LOGO_DARK' => '/brand-assets/logo_dark.svg',
    # The URL that would be used in emails under the section "Powered By"
    'BRAND_URL' => 'https://www.chatwoot.com',
    # The URL that would be used in the widget under the section "Powered By"
    'WIDGET_BRAND_URL' => 'https://www.chatwoot.com',
    # The name that would be used in emails and the widget
    'BRAND_NAME' => 'Chatwoot',
    # The terms of service URL displayed in Signup Page
    'TERMS_URL' => 'https://www.chatwoot.com/terms-of-service',
    # The privacy policy URL displayed in the app
    'PRIVACY_URL' => 'https://www.chatwoot.com/privacy-policy',
    # Display default Chatwoot metadata like favicons and upgrade warnings
    'DISPLAY_MANIFEST' => true
  }.freeze

  def self.resolve_value(config_name, default_value)
    if default_value.in?([true, false])
      ENV.fetch(config_name, default_value.to_s) == 'true'
    else
      ENV.fetch(config_name, default_value)
    end
  end

  def self.update_installation_config_file
    config_path = Rails.root.join('enterprise/config/premium_installation_config.yml')
    config = YAML.safe_load_file(config_path)

    CONFIGURABLE_ITEMS.each do |config_name, default_value|
      value = resolve_value(config_name, default_value)
      entry = config.find { |c| c['name'] == config_name }
      next unless entry

      entry['value'] = value
      puts "Config file: updated '#{config_name}' to '#{value}'."
    end

    File.write(config_path, config.to_yaml)
  end

  def self.update_database
    CONFIGURABLE_ITEMS.each do |config_name, default_value|
      value = resolve_value(config_name, default_value)
      InstallationConfig.find_by!(name: config_name).update!(value: value)
      puts "Database: updated '#{config_name}' to '#{value}'."
    end
  end
end

namespace :branding do
  desc 'Updates branding configurations from environment variables or defaults'
  task update: :environment do
    BrandingTaskHelper.update_installation_config_file
    BrandingTaskHelper.update_database
    puts 'Branding configuration update finished.'
  end
end
