# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstallationConfig do
  it { is_expected.to validate_presence_of(:name) }

  describe 'protected fazer.ai config keys' do
    let(:protected_keys) { described_class::PROTECTED_SUBSCRIPTION_KEYS }

    context 'when not in trusted context' do
      it 'prevents creating protected fazer.ai config' do
        config = described_class.new(name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: 'fake_token')

        expect(config.valid?).to be(false)
        expect(config.errors[:base]).to include('Protected subscription configuration cannot be modified directly')
      end

      it 'prevents updating protected fazer.ai config' do
        Current.set(fazer_ai_trusted_subscription_update: true) do
          described_class.create!(name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: 'original_token')
        end

        config = described_class.find_by(name: 'FAZER_AI_SUBSCRIPTION_TOKEN')
        config.value = 'modified_token'

        expect(config.valid?).to be(false)
        expect(config.errors[:base]).to include('Protected subscription configuration cannot be modified directly')
      end

      it 'allows creating non-protected config' do
        config = described_class.new(name: 'SOME_OTHER_CONFIG', value: 'some_value')

        expect(config.valid?).to be(true)
      end
    end

    context 'when in trusted context' do
      it 'allows creating protected fazer.ai config' do
        Current.set(fazer_ai_trusted_subscription_update: true) do
          config = described_class.new(name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: 'valid_token')

          expect(config.valid?).to be(true)
        end
      end

      it 'allows updating protected fazer.ai config' do
        Current.set(fazer_ai_trusted_subscription_update: true) do
          described_class.create!(name: 'FAZER_AI_SUBSCRIPTION_TOKEN', value: 'original_token')
          config = described_class.find_by(name: 'FAZER_AI_SUBSCRIPTION_TOKEN')
          config.value = 'updated_token'

          expect(config.valid?).to be(true)
          expect(config.save).to be(true)
        end
      end
    end
  end
end
