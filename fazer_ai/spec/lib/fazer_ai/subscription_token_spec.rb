# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::SubscriptionToken do
  include FazerAi::SubscriptionTokenTestHelper

  describe '.verify' do
    context 'with valid token' do
      let(:token) do
        generate_test_subscription_token(
          status: 'active',
          features: { 'kanban' => { 'account_limit' => 5 } }
        )
      end

      it 'returns the decoded payload' do
        payload = described_class.verify(token)

        expect(payload).to be_present
        expect(payload['status']).to eq('active')
        expect(payload['features']).to eq({ 'kanban' => { 'account_limit' => 5 } })
      end

      it 'returns payload with indifferent access' do
        payload = described_class.verify(token)

        expect(payload[:status]).to eq('active')
        expect(payload['status']).to eq('active')
      end
    end

    context 'with blank token' do
      it 'returns nil for nil token' do
        expect(described_class.verify(nil)).to be_nil
      end

      it 'returns nil for empty string token' do
        expect(described_class.verify('')).to be_nil
      end
    end

    context 'with invalid token' do
      it 'returns nil for malformed token' do
        expect(described_class.verify('invalid.token.here')).to be_nil
      end

      it 'returns nil for token with wrong signature' do
        # Generate token with different private key
        different_key = OpenSSL::PKey::RSA.new(2048)
        payload = { status: 'active', installation_identifier: ChatwootHub.installation_identifier }
        bad_token = JWT.encode(payload, different_key, 'RS256')

        expect(described_class.verify(bad_token)).to be_nil
      end
    end

    context 'with token for different installation' do
      let(:token) do
        generate_test_subscription_token(
          status: 'active',
          installation_identifier: 'different-installation-id'
        )
      end

      it 'returns nil' do
        expect(described_class.verify(token)).to be_nil
      end
    end

    context 'with missing required fields' do
      it 'returns nil when status is missing' do
        private_key = OpenSSL::PKey::RSA.new(FazerAi::SubscriptionTokenTestHelper::TEST_PRIVATE_KEY)
        payload = {
          installation_identifier: ChatwootHub.installation_identifier,
          iat: Time.current.to_i,
          exp: 48.hours.from_now.to_i
        }
        token = JWT.encode(payload, private_key, 'RS256')

        expect(described_class.verify(token)).to be_nil
      end

      it 'returns nil when installation_identifier is missing' do
        private_key = OpenSSL::PKey::RSA.new(FazerAi::SubscriptionTokenTestHelper::TEST_PRIVATE_KEY)
        payload = {
          status: 'active',
          iat: Time.current.to_i,
          exp: 48.hours.from_now.to_i
        }
        token = JWT.encode(payload, private_key, 'RS256')

        expect(described_class.verify(token)).to be_nil
      end
    end
  end

  describe '.valid?' do
    it 'returns true for valid token' do
      token = generate_test_subscription_token(status: 'active')
      expect(described_class.valid?(token)).to be(true)
    end

    it 'returns false for invalid token' do
      expect(described_class.valid?('invalid-token')).to be(false)
    end

    it 'returns false for nil' do
      expect(described_class.valid?(nil)).to be(false)
    end
  end

  describe '.verified_recently?' do
    it 'returns true when verified within token validity window' do
      verified_at = 1.hour.ago.iso8601
      expect(described_class.verified_recently?(verified_at)).to be(true)
    end

    it 'returns true when verified at window boundary' do
      verified_at = (described_class::TOKEN_VALIDITY_HOURS - 1).hours.ago.iso8601
      expect(described_class.verified_recently?(verified_at)).to be(true)
    end

    it 'returns false when verification is stale' do
      verified_at = (described_class::TOKEN_VALIDITY_HOURS + 1).hours.ago.iso8601
      expect(described_class.verified_recently?(verified_at)).to be(false)
    end

    it 'returns false for blank value' do
      expect(described_class.verified_recently?(nil)).to be(false)
      expect(described_class.verified_recently?('')).to be(false)
    end

    it 'returns false for invalid date string' do
      expect(described_class.verified_recently?('not-a-date')).to be(false)
    end

    it 'accepts Time objects' do
      expect(described_class.verified_recently?(1.hour.ago)).to be(true)
      expect(described_class.verified_recently?(4.days.ago)).to be(false)
    end
  end

  describe '.generate' do
    it 'generates a valid token' do
      payload = { status: 'active', installation_identifier: ChatwootHub.installation_identifier }
      token = described_class.generate(payload, FazerAi::SubscriptionTokenTestHelper::TEST_PRIVATE_KEY)

      expect(token).to be_present
      expect(described_class.verify(token)).to be_present
    end

    it 'includes iat and exp claims' do
      payload = { status: 'active', installation_identifier: ChatwootHub.installation_identifier }
      token = described_class.generate(payload, FazerAi::SubscriptionTokenTestHelper::TEST_PRIVATE_KEY)

      decoded = described_class.verify(token)
      expect(decoded['iat']).to be_present
      expect(decoded['exp']).to be_present
      expect(decoded['exp'] - decoded['iat']).to eq(described_class::TOKEN_VALIDITY_HOURS * 3600)
    end
  end
end
