require 'rails_helper'

RSpec.describe Channels::Whatsapp::BaileysUpdateContactAvatarJob do
  let(:whatsapp_channel) { create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: whatsapp_channel.account) }
  let(:phone) { '5511987654321' }
  let(:provider) { instance_double(Whatsapp::Providers::WhatsappBaileysService) }

  before do
    allow(inbox.channel).to receive(:provider_service).and_return(provider)
  end

  it 'enqueues on the low queue' do
    expect { described_class.perform_later(contact, inbox, phone) }.to have_enqueued_job(described_class).on_queue('low')
  end

  context 'when the contact already has an avatar attached' do
    before do
      allow(contact).to receive(:avatar).and_return(instance_double(ActiveStorage::Attached::One, attached?: true))
    end

    it 'does not call the provider' do
      described_class.perform_now(contact, inbox, phone)

      expect(provider).not_to have_received(:get_profile_pic) if provider.respond_to?(:get_profile_pic)
    end
  end

  context 'when the provider returns a profile picture url' do
    before do
      allow(provider).to receive(:get_profile_pic)
        .with("#{phone}@s.whatsapp.net")
        .and_return({ 'data' => { 'profilePictureUrl' => 'https://pps.whatsapp.net/avatar.jpg' } })
    end

    it 'enqueues the avatar download job' do
      expect { described_class.perform_now(contact, inbox, phone) }
        .to have_enqueued_job(Avatar::AvatarFromUrlJob)
        .with(contact, 'https://pps.whatsapp.net/avatar.jpg')
    end
  end

  context 'when the provider returns no url' do
    before do
      allow(provider).to receive(:get_profile_pic).and_return({ 'data' => { 'profilePictureUrl' => nil } })
    end

    it 'does not enqueue the avatar download job' do
      expect { described_class.perform_now(contact, inbox, phone) }.not_to have_enqueued_job(Avatar::AvatarFromUrlJob)
    end
  end

  context 'when the provider raises' do
    before do
      allow(provider).to receive(:get_profile_pic).and_raise(StandardError, 'baileys down')
    end

    it 'rescues and logs without propagating' do
      expect(Rails.logger).to receive(:error).with(/baileys down/)
      expect { described_class.perform_now(contact, inbox, phone) }.not_to raise_error
    end
  end
end
