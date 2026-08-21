require 'rails_helper'

RSpec.describe Whatsapp::Session::Errors do
  # Resolved inside the example, never captured from `described_class`. A reload between
  # loading this file and running it replaces the module object, and RSpec keeps holding
  # the old one, whose child classes are no longer the ones the legacy errors inherit
  # from: `be_a` then fails against a class that looks identical. Referencing the
  # constant here re-resolves it.
  let(:errors) { Whatsapp::Session::Errors } # rubocop:disable RSpec/DescribedClass

  it 'is what the legacy providers raise, so callers rescue a single namespace' do
    expect(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError.new).to be_a(errors::ProviderUnavailable)
    expect(Whatsapp::Providers::WhatsappZapiService::ProviderUnavailableError.new).to be_a(errors::ProviderUnavailable)
    expect(Whatsapp::Providers::WhatsappBaileysService::GroupParticipantNotAllowedError.new)
      .to be_a(errors::GroupParticipantNotAllowed)
    expect(Whatsapp::Providers::WhatsappBaileysService::MessageAlreadyProcessingError.new)
      .to be_a(errors::MessageAlreadyProcessing)
  end

  it 'treats a connection that is not usable right now as unavailable' do
    expect(errors::NotConnected.new).to be_a(errors::ProviderUnavailable)
    expect(errors::Quarantined.new).to be_a(errors::ProviderUnavailable)
    expect(errors::ClientOutdated.new).to be_a(errors::ProviderUnavailable)
  end

  describe '.build' do
    it 'maps a wire code back to its class' do
      expect(errors.build('media_too_large')).to be_a(errors::MediaTooLarge)
      expect(errors.build('not_connected', 'session is down')).to have_attributes(message: 'session is down')
    end

    it 'degrades an unknown code instead of failing the consumer' do
      expect(errors.build('teleportation_failed')).to be_a(errors::Internal)
    end
  end

  it 'exposes the wire code of each class' do
    expect(errors::RateLimited.new.code).to eq('rate_limited')
    expect(errors::NotSupported.new.code).to eq('unsupported')
  end
end
