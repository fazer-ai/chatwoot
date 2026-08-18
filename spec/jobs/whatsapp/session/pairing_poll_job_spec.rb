require 'rails_helper'

RSpec.describe Whatsapp::Session::PairingPollJob do
  let(:channel) do
    create(:channel_whatsapp, provider: 'uazapi', validate_provider_config: false, sync_templates: false)
  end
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }

  before do
    allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend)
    allow(backend.class).to receive(:state_polling?).and_return(true)
  end

  def state(connection, **attrs)
    Whatsapp::Session::Model::ConnectionState.new(connection: connection, **attrs)
  end

  it 'writes the rotated QR and asks for another round while the session is still connecting' do
    allow(backend).to receive(:fetch_connection_state).and_return(state('connecting', qr_data_url: 'data:image/png;base64,ROTATED'))

    expect { described_class.perform_now(channel) }.to have_enqueued_job(described_class)
    expect(channel.reload.provider_connection['qr_data_url']).to eq('data:image/png;base64,ROTATED')
  end

  it 'stops as soon as the session is paired' do
    allow(backend).to receive(:fetch_connection_state).and_return(state('open', phone_number: '5541988887777'))

    expect { described_class.perform_now(channel) }.not_to have_enqueued_job(described_class)
    expect(channel.reload.provider_connection['connection']).to eq('open')
  end

  it 'stops at the ceiling instead of polling a pairing nobody completed' do
    allow(backend).to receive(:fetch_connection_state).and_return(state('connecting'))

    expect do
      described_class.perform_now(channel, pairing: 'qr', deadline_at: 10.seconds.from_now)
    end.not_to have_enqueued_job(described_class)
  end

  it 'gives a pairing code longer than a QR, since the operator has to type it' do
    expect(described_class::DEADLINES['code']).to be > described_class::DEADLINES['qr']
  end

  it 'does not poll a backend that pushes its own state' do
    allow(backend.class).to receive(:state_polling?).and_return(false)
    allow(backend).to receive(:fetch_connection_state)

    described_class.perform_now(channel)

    expect(backend).not_to have_received(:fetch_connection_state)
  end

  it 'gives up quietly when the instance is unreachable mid-pairing' do
    allow(backend).to receive(:fetch_connection_state).and_raise(Whatsapp::Session::Errors::ProviderUnavailable)

    expect { described_class.perform_now(channel) }.not_to raise_error
  end
end
