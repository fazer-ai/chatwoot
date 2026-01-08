# frozen_string_literal: true

module FazerAi::SubscriptionToken
  TOKEN_VALIDITY_HOURS = 72

  PUBLIC_KEY = <<~PEM
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsfA55RDBWZQWkb/akx8e
    Invy8WQgcKK7TPk6HF9FSrpSKeYNUHbCZqfHYt3vEChYISVYnpzE6sGo63XxPr+p
    ABJlA56rKapoGidds1F08kjt17qbEDb+Yw1Y1hvKmK/pugk+RiePNVFU9AJRCALc
    TasAFTSu80Dw81fPi/E+ipSFWFK6r3UgUuB+eGR83EXQJBpXSs0mLbxgHNpHqDvj
    OalxSImTf2nJn/R188gTfC308VC5a3OW3kVhN2Bj6ugWh6EXQVjGXUQJ0V0yPsUi
    R1GgXfqITsApHmE53gLenb/OYRnzgRWxd3sJv2cpV6SrYeyzjlJIdoRsl9OHwUMa
    GwIDAQAB
    -----END PUBLIC KEY-----
  PEM

  # Enable by setting FAZER_AI_HUB_URL to a localhost URL
  TEST_PUBLIC_KEY = <<~PEM
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr9ICjCbXqQxIS7jmSaeG
    5ifkpEzM0dc9/YCmTW/wVClVDpgRCUpNgCeXG45PX8/LDa1JLgoyeBjCdaHMgLpb
    1I9ssWCMKBXOfHd9HsswCosWacbwiM7ZiLhByAh1KgUAYV5KTbGgJM9Bf/JPv6L4
    b08FRb67OO4gdQxRQljY5ibj8MfF1NeB9c6PKWa41CAhkVGr+bktoL8lfQ357a2F
    N8o2wr/TzlH/SvTK7GZp61ZBJQ9hsKuxvQ0IBib2kem2aHEvRtMZ2AIrTCkmspAJ
    ReAtw7sC/gVAheqw0qGcYBQsF4gK06L60oj8NAra1diA+WPlCE3wD5365iaZLmIf
    TQIDAQAB
    -----END PUBLIC KEY-----
  PEM

  class << self
    def verify(token)
      return nil if token.blank?

      payload = decode_token(token)
      payload ? validate_payload(payload) : nil
    rescue JWT::ExpiredSignature
      Rails.logger.warn('[fazer.ai] Subscription token expired')
      nil
    rescue JWT::InvalidIatError
      Rails.logger.warn('[fazer.ai] Subscription token has invalid iat')
      nil
    rescue JWT::DecodeError => e
      Rails.logger.warn("[fazer.ai] Subscription token decode error: #{e.message}")
      nil
    end

    def valid?(token)
      verify(token).present?
    end

    def verified_recently?(verified_at)
      return false if verified_at.blank?

      time = verified_at.is_a?(Time) ? verified_at : Time.zone.parse(verified_at.to_s)
      return false if time.nil?

      time > TOKEN_VALIDITY_HOURS.hours.ago
    rescue ArgumentError
      false
    end

    def generate(payload, private_key_pem)
      private_key = OpenSSL::PKey::RSA.new(private_key_pem)

      JWT.encode(
        payload.merge(
          iat: Time.current.to_i,
          exp: TOKEN_VALIDITY_HOURS.hours.from_now.to_i
        ),
        private_key,
        'RS256'
      )
    end

    private

    def decode_token(token)
      JWT.decode(token, public_key, true, { algorithm: 'RS256', verify_expiration: true, verify_iat: true }).first
    end

    def public_key
      @public_key ||= OpenSSL::PKey::RSA.new(use_test_key? ? TEST_PUBLIC_KEY : PUBLIC_KEY)
    end

    def use_test_key?
      hub_url = ENV.fetch('FAZER_AI_HUB_URL', nil)
      return false if hub_url.blank?

      uri = URI.parse(hub_url)
      uri.host == 'localhost' || uri.host == '127.0.0.1'
    rescue URI::InvalidURIError
      false
    end

    def validate_payload(payload)
      required_fields = %w[status installation_identifier]
      return nil unless required_fields.all? { |f| payload[f].present? }
      return nil unless payload['installation_identifier'] == ChatwootHub.installation_identifier

      payload.with_indifferent_access
    end
  end
end
