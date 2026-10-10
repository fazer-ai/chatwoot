require 'rails_helper'

# Calling on a paired phone: the connector carries it, so turning it on is the inbox's flag
# and the connect that tells the connector, and nothing at all is asked of Meta.
RSpec.describe Whatsapp::Session::ChannelExtension do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'native', validate_provider_config: false, sync_templates: false)
  end

  let(:carries_calls) { true }

  before do
    account.enable_features!('channel_voice')
    allow(Whatsapp::Connector::Client).to receive(:carries_calls?) { carries_calls }
  end

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

  # The pairing under way was connected with the policy from before, and nothing connects
  # it again once paired.
  it 'tells the connector about calling turned on during the pairing, once it succeeds' do
    channel.update!(provider_connection: { 'connection' => 'connecting', 'qr_data_url' => 'data:image/png;base64,AA' })
    expect { channel.enable_voice_calling! }.not_to have_enqueued_job(Whatsapp::Session::ApplyProxyJob)

    model = Whatsapp::Session::Model
    paired = model::Event.build(model::Events::PairingSuccess.new(phone: channel.phone_number.delete('+'), lid: '99887766'), epoch: 1)
    expect { Whatsapp::Session::Inbound::Handlers::ConnectionState.new(channel: channel.reload, event: paired).perform }
      .to have_enqueued_job(Whatsapp::Session::ApplyProxyJob).with(channel.id)
  end

  it 'still tells the connector when the pairing event is redelivered after the job could not be enqueued' do
    channel.update!(provider_connection: { 'connection' => 'connecting', 'qr_data_url' => 'data:image/png;base64,AA' })
    channel.enable_voice_calling!
    model = Whatsapp::Session::Model
    paired = model::Event.build(model::Events::PairingSuccess.new(phone: channel.phone_number.delete('+'), lid: '99887766'), epoch: 1)
    handle = -> { Whatsapp::Session::Inbound::Handlers::ConnectionState.new(channel: channel.reload, event: paired).perform }
    allow(Whatsapp::Session::ApplyProxyJob).to receive(:perform_later).and_raise(Redis::CannotConnectError, 'down')
    expect(&handle).to raise_error(Redis::CannotConnectError)

    allow(Whatsapp::Session::ApplyProxyJob).to receive(:perform_later).and_call_original
    expect(&handle).to have_enqueued_job(Whatsapp::Session::ApplyProxyJob).with(channel.id)
  end

  it 'does not connect again a pairing that succeeds with nothing changed under it' do
    channel.update!(provider_connection: { 'connection' => 'connecting', 'qr_data_url' => 'data:image/png;base64,AA' })

    model = Whatsapp::Session::Model
    paired = model::Event.build(model::Events::PairingSuccess.new(phone: channel.phone_number.delete('+'), lid: '99887766'), epoch: 1)
    expect { Whatsapp::Session::Inbound::Handlers::ConnectionState.new(channel: channel.reload, event: paired).perform }
      .not_to have_enqueued_job(Whatsapp::Session::ApplyProxyJob)
  end

  it 'does not turn calling on for an inbox that leaves through a proxy, and still turns it off' do
    channel.update!(provider_config: channel.provider_config.merge('proxy_url' => 'http://proxy.example:3128'))

    expect { channel.reload.enable_voice_calling! }
      .to raise_error(RuntimeError, I18n.t('errors.whatsapp.calls.proxy_unsupported'))
    channel.disable_voice_calling!
    expect(channel.reload.provider_config['calling_enabled']).to be(false)
  end

  # Left on, the inbox would read as calling while the connector refuses every call on it.
  it 'turns calling off when a proxy is saved on an inbox that calls, and tells the connector' do
    channel.enable_voice_calling!
    channel.update!(provider_connection: { 'connection' => 'open' })

    expect { channel.reload.update!(provider_config: channel.provider_config.merge('proxy_url' => 'http://proxy.example:3128')) }
      .to have_enqueued_job(Whatsapp::Session::ApplyProxyJob).with(channel.id)
    expect(channel.reload.provider_config).to include('calling_enabled' => false, 'proxy_url' => 'http://proxy.example:3128')
    expect(channel.voice_enabled?).to be(false)
  end

  it 'leaves calling alone when the proxy is taken off' do
    channel.update!(provider_config: channel.provider_config.merge('proxy_url' => 'http://proxy.example:3128'))
    channel.reload.update!(provider_config: channel.provider_config.merge('proxy_url' => ''))
    channel.reload.enable_voice_calling!

    expect(channel.reload.provider_config['calling_enabled']).to be(true)
  end

  context 'when the connector does not carry call voice' do
    let(:carries_calls) { false }

    it 'does not turn calling on, says why, and still turns it off' do
      expect { channel.enable_voice_calling! }
        .to raise_error(RuntimeError, I18n.t('errors.whatsapp.calls.connector_without_calls'))
      expect(channel.reload.provider_config['calling_enabled']).to be_nil
      expect(channel.voice_calls_carried?).to be(false)

      channel.disable_voice_calling!
      expect(channel.reload.provider_config['calling_enabled']).to be(false)
    end
  end

  it 'leaves calling on a Cloud inbox to the Calling API' do
    cloud = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)

    expect(cloud.voice_calling_supported?).to be(true)
  end

  # Uazapi pairs a phone and has no way to carry a call's voice.
  it 'does not offer calling on a session provider that cannot carry it' do
    allow(channel).to receive(:session_capabilities).and_return(%w[calls])

    expect(channel.voice_calling_supported?).to be(false)
    expect { channel.enable_voice_calling! }.to raise_error(RuntimeError, I18n.t('errors.whatsapp.calls.provider_unsupported'))
    expect(channel.reload.provider_config['calling_enabled']).to be_nil
  end

  it 'refuses calling on an account without voice' do
    account.disable_features!('channel_voice')

    expect { channel.enable_voice_calling! }.to raise_error(RuntimeError, I18n.t('errors.whatsapp.calls.channel_voice_required'))
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
