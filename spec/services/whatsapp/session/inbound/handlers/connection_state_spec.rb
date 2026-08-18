require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::ConnectionState do
  subject(:dispatch) { Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event) }

  let(:channel) do
    create(:channel_whatsapp, provider: 'native', phone_number: '+5541988887777',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  let(:model) { Whatsapp::Session::Model }
  let(:event) { model::Event.build(model::Events::SessionState.new(state: 'open', phone: '5541988887777'), epoch: 2) }

  before { allow(channel).to receive(:provider_service).and_return(backend) }

  it 'writes the connection the provider reports' do
    expect(dispatch).to eq(:handled)

    expect(channel.reload.provider_connection).to include('connection' => 'open', 'phone_number' => '5541988887777', 'epoch' => 2)
  end

  it 'keeps the QR of a pairing event' do
    event = model::Event.build(model::Events::PairingQr.new(png_data_url: 'data:image/png;base64,AAA'), epoch: 1)
    described_class.new(channel: channel, event: event).perform

    expect(channel.reload.provider_connection).to include('connection' => 'connecting', 'qr_data_url' => 'data:image/png;base64,AAA')
  end

  # The wire carries a key and the writer stores the sentence, because an Action Cable
  # broadcast has no single reader whose locale could be used on read.
  it 'turns a session that died into the sentence the dashboard renders' do
    event = model::Event.build(model::Events::SessionLoggedOut.new(reason: 'device_removed'), epoch: 3)
    described_class.new(channel: channel, event: event).perform

    expect(channel.reload.provider_connection).to include(
      'connection' => 'close', 'error' => I18n.t('errors.inboxes.channel.provider_connection.logged_out')
    )
  end

  it 'discards an event from a previous owner of the session' do
    dispatch
    stale = model::Event.build(model::Events::SessionState.new(state: 'close'), epoch: 1)

    expect(described_class.new(channel: channel, event: stale).perform).to eq(:ignored)
    expect(channel.reload.provider_connection['connection']).to eq('open')
  end

  context 'when a different number was paired' do
    let(:event) { model::Event.build(model::Events::PairingSuccess.new(phone: '5541900001111', lid: '99887766'), epoch: 1) }

    it 'refuses the session and says why' do
      expect(dispatch).to eq(:handled)

      expect(channel.reload.provider_connection).to include(
        'connection' => 'close', 'error' => I18n.t('errors.inboxes.channel.provider_connection.wrong_phone_number')
      )
      expect(backend.commands_of('session.logout').size).to eq(1)
    end
  end

  # The inbox is configured as +55 41 98888-7777 and WhatsApp reports the same line as
  # 554188887777, because Brazilian numbers registered before the ninth digit are still
  # addressed without it. Comparing the raw digits would log the operator out of the
  # very number they configured.
  context 'when the paired number is the configured one without its ninth digit' do
    let(:event) { model::Event.build(model::Events::PairingSuccess.new(phone: '554188887777', lid: '99887766'), epoch: 1) }

    it 'accepts the session' do
      expect(dispatch).to eq(:handled)

      expect(channel.reload.provider_connection['error']).to be_blank
      expect(backend.commands_of('session.logout')).to be_empty
    end
  end

  it 'keeps the account limits a poll wrote while the state changes' do
    channel.update_provider_connection!({ 'connection' => 'open', 'reachout_time_lock' => { 'until' => 123 } })
    described_class.new(channel: channel, event: model::Event.build(model::Events::SessionState.new(state: 'connecting'))).perform

    expect(channel.reload.provider_connection).to include('connection' => 'connecting', 'reachout_time_lock' => { 'until' => 123 })
  end
end
