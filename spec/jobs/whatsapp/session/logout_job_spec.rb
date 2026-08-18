require 'rails_helper'

RSpec.describe Whatsapp::Session::LogoutJob do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }

  before { allow(channel).to receive(:provider_service).and_return(backend) }

  it 'asks the session to end' do
    described_class.perform_now(channel)

    expect(backend.commands_of('session.logout').size).to eq(1)
  end

  # The caller has already written the refusal, so a repeat of the same event reports as
  # unchanged and never reaches the logout again: swallowing a transient failure would
  # leave the wrong WhatsApp account connected with nobody asking it to stop.
  it 'lets a transient failure out so the retry can see it' do
    allow(backend).to receive(:logout).and_raise(Whatsapp::Session::Errors::ProviderUnavailable)

    expect { described_class.new.perform(channel) }.to raise_error(Whatsapp::Session::Errors::ProviderUnavailable)
  end

  it 'gives up on a failure no retry can fix' do
    allow(backend).to receive(:logout).and_raise(Whatsapp::Session::Errors::NotSupported)

    expect { described_class.new.perform(channel) }.not_to raise_error
  end
end
