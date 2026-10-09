require 'rails_helper'

# Calling on a paired phone: the connector carries it, so turning it on is the inbox's flag
# and the connect that tells the connector, and nothing at all is asked of Meta.
RSpec.describe Whatsapp::Session::ChannelExtension do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'native', validate_provider_config: false, sync_templates: false)
  end

  before { account.enable_features!('channel_voice') }

  it 'supports calling on the native provider and turns it on and off without reaching Meta' do
    expect(channel.voice_calling_supported?).to be(true)

    channel.enable_voice_calling!
    expect(channel.reload.provider_config['calling_enabled']).to be(true)
    expect(channel.voice_enabled?).to be(true)

    channel.disable_voice_calling!
    expect(channel.reload.provider_config['calling_enabled']).to be(false)
    expect(channel.voice_enabled?).to be(false)

    expect(a_request(:any, //)).not_to have_been_made
  end

  it 'leaves calling on a Cloud inbox to the Calling API' do
    cloud = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)

    expect(cloud.voice_calling_supported?).to be(true)
  end

  # Uazapi pairs a phone and has no way to carry a call's voice.
  it 'does not offer calling on a session provider that cannot carry it' do
    allow(channel).to receive(:session_capabilities).and_return(%w[calls])

    expect(channel.voice_calling_supported?).to be(false)
    expect { channel.enable_voice_calling! }.to raise_error(RuntimeError, /not supported/)
    expect(channel.reload.provider_config['calling_enabled']).to be_nil
  end

  it 'refuses calling on an account without voice' do
    account.disable_features!('channel_voice')

    expect { channel.enable_voice_calling! }.to raise_error(RuntimeError, /channel_voice/)
  end

  # The call policy rides on the connect and the connector keeps the last one it was given,
  # so a paired session has to be connected again for the switch to mean anything.
  describe 'telling the connector' do
    before { channel.update!(provider_connection: { 'connection' => 'open' }) }

    it 'connects a paired session again when calling is switched' do
      expect { channel.enable_voice_calling! }.to have_enqueued_job(Whatsapp::Session::ApplyProxyJob).with(channel.id)
      expect { channel.disable_voice_calling! }.to have_enqueued_job(Whatsapp::Session::ApplyProxyJob).with(channel.id)
    end

    # Off is off, whether the flag was never written or was written false.
    it 'does not reconnect for calling turned off on an inbox that never had it' do
      expect { channel.disable_voice_calling! }.not_to have_enqueued_job(Whatsapp::Session::ApplyProxyJob)
    end

    it 'does not reconnect for a save that leaves calling as it was' do
      channel.enable_voice_calling!

      expect { channel.update!(provider_config: channel.provider_config.merge('mark_as_read' => true)) }
        .not_to have_enqueued_job(Whatsapp::Session::ApplyProxyJob)
    end

    it 'leaves a session that is not paired to its next connect' do
      channel.update!(provider_connection: { 'connection' => 'close' })

      expect { channel.enable_voice_calling! }.not_to have_enqueued_job(Whatsapp::Session::ApplyProxyJob)
    end
  end
end
