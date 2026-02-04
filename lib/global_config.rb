class GlobalConfig
  VERSION = 'V1'.freeze
  KEY_PREFIX = 'GLOBAL_CONFIG'.freeze
  DEFAULT_EXPIRY = 1.day

  BRANDING_CONFIGS = {
    'INSTALLATION_NAME' => { default: 'Chatwoot', type: :string },
    'LOGO_THUMBNAIL' => { default: '/brand-assets/logo_thumbnail.svg', type: :string },
    'LOGO' => { default: '/brand-assets/logo.svg', type: :string },
    'LOGO_DARK' => { default: '/brand-assets/logo_dark.svg', type: :string },
    'BRAND_URL' => { default: 'https://www.chatwoot.com', type: :string },
    'WIDGET_BRAND_URL' => { default: 'https://www.chatwoot.com', type: :string },
    'BRAND_NAME' => { default: 'Chatwoot', type: :string },
    'TERMS_URL' => { default: 'https://www.chatwoot.com/terms-of-service', type: :string },
    'PRIVACY_URL' => { default: 'https://www.chatwoot.com/privacy-policy', type: :string },
    'DISPLAY_MANIFEST' => { default: true, type: :boolean }
  }.freeze

  class << self
    def get(*args)
      config_keys = *args
      config = {}

      config_keys.each do |config_key|
        config[config_key] = load_from_cache(config_key)
      end

      typecast_config(config)
      config.with_indifferent_access
    end

    def get_value(arg)
      load_from_cache(arg)
    end

    def clear_cache
      cached_keys = $alfred.with { |conn| conn.keys("#{VERSION}:#{KEY_PREFIX}:*") }
      (cached_keys || []).each do |cached_key|
        $alfred.with { |conn| conn.expire(cached_key, 0) }
      end
    end

    private

    def typecast_config(config)
      general_configs = ConfigLoader.new.general_configs
      config.each do |config_key, config_value|
        config_type = general_configs.find { |c| c['name'] == config_key }&.dig('type')
        config[config_key] = ActiveRecord::Type::Boolean.new.cast(config_value) if config_type == 'boolean'
      end
    end

    def load_from_cache(config_key)
      env_value = branding_env_override(config_key)
      return env_value unless env_value.nil?

      cache_key = "#{VERSION}:#{KEY_PREFIX}:#{config_key}"
      cached_value = $alfred.with { |conn| conn.get(cache_key) }

      if cached_value.blank?
        value_from_db = db_fallback(config_key)
        cached_value = { value: value_from_db }.to_json
        $alfred.with { |conn| conn.set(cache_key, cached_value, { ex: DEFAULT_EXPIRY }) }
      end

      JSON.parse(cached_value)['value']
    end

    def branding_env_override(config_key)
      branding_config = BRANDING_CONFIGS[config_key]
      return nil unless branding_config

      env_value = ENV.fetch(config_key, nil)
      return nil if env_value.nil?

      # Don't override if ENV value matches default (user hasn't customized)
      return nil if env_value == branding_config[:default].to_s

      if branding_config[:type] == :boolean
        env_value == 'true'
      else
        env_value
      end
    end

    def db_fallback(config_key)
      InstallationConfig.find_by(name: config_key)&.value
    end
  end
end
