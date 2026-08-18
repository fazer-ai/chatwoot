require 'rails_helper'

RSpec.describe Whatsapp::Session::LogoutJob do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }

  before do
    allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend)
    # The quarantine is the whole reason this job is ever enqueued.
    channel.update_provider_connection!({ 'connection' => 'close', 'error_code' => 'wrong_phone_number' })
  end

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

  # A retry of this job can run minutes after the rejection that queued it. By then the
  # administrator may have corrected the number and paired again, and logging out would
  # kill the session that replaced the one this was sent to remove.
  it 'does nothing once the inbox is no longer disowned' do
    channel.update_provider_connection!({ 'connection' => 'open', 'phone_number' => '5541988887777' })

    described_class.perform_now(channel)

    expect(backend.commands_of('session.logout')).to be_empty
  end
end
