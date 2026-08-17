require 'rails_helper'

RSpec.describe Whatsapp::Session::Errors do
  it 'is what the legacy providers raise, so callers rescue a single namespace' do
    expect(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError.new).to be_a(described_class::ProviderUnavailable)
    expect(Whatsapp::Providers::WhatsappZapiService::ProviderUnavailableError.new).to be_a(described_class::ProviderUnavailable)
    expect(Whatsapp::Providers::WhatsappBaileysService::GroupParticipantNotAllowedError.new)
      .to be_a(described_class::GroupParticipantNotAllowed)
    expect(Whatsapp::Providers::WhatsappBaileysService::MessageAlreadyProcessingError.new)
      .to be_a(described_class::MessageAlreadyProcessing)
  end

  it 'treats a connection that is not usable right now as unavailable' do
    expect(described_class::NotConnected.new).to be_a(described_class::ProviderUnavailable)
    expect(described_class::Quarantined.new).to be_a(described_class::ProviderUnavailable)
    expect(described_class::ClientOutdated.new).to be_a(described_class::ProviderUnavailable)
  end

  describe '.build' do
    it 'maps a wire code back to its class' do
      expect(described_class.build('media_too_large')).to be_a(described_class::MediaTooLarge)
      expect(described_class.build('not_connected', 'session is down')).to have_attributes(message: 'session is down')
    end

    it 'degrades an unknown code instead of failing the consumer' do
      expect(described_class.build('teleportation_failed')).to be_a(described_class::Internal)
    end
  end

  it 'exposes the wire code of each class' do
    expect(described_class::RateLimited.new.code).to eq('rate_limited')
    expect(described_class::NotSupported.new.code).to eq('unsupported')
  end
end
