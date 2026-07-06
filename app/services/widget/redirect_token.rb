class Widget::RedirectToken
  DEFAULT_TTL = 24.hours.to_i
  KEY_PREFIX = 'WIDGET_REDIRECT_TOKEN'.freeze

  class << self
    def generate(payload, ttl: DEFAULT_TTL)
      token = SecureRandom.urlsafe_base64(18)
      ::Redis::Alfred.set(key(token), payload.to_json, ex: ttl)
      token
    end

    def consume(token)
      return if token.blank?

      raw = ::Redis::Alfred.get(key(token))
      return if raw.blank?

      ::Redis::Alfred.delete(key(token))
      JSON.parse(raw)
    end

    private

    def key(token)
      "#{KEY_PREFIX}::#{token}"
    end
  end
end
