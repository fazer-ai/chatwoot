require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::StatusTransition do
  let(:message) { create(:message, status: :sent) }

  it 'moves a message forward' do
    expect(described_class.apply(message, 'delivered')).to be(true)
    expect(message.reload.status).to eq('delivered')
  end

  it 'treats a played voice note as read' do
    expect(described_class.apply(message, 'played')).to be(true)
    expect(message.reload.status).to eq('read')
  end

  it 'never walks a status back' do
    message.update!(status: :read)

    expect(described_class.apply(message, 'delivered')).to be(false)
    expect(message.reload.status).to eq('read')
  end

  it 'ignores a receipt type it does not know' do
    expect(described_class.apply(message, 'teleported')).to be(false)
  end

  it 'keeps the provider reason on a failure' do
    error = Whatsapp::Session::Model::WireError.new(code: 'media_too_large', message: 'file is too big')

    expect(described_class.apply(message, 'failed', error: error)).to be(true)
    expect(message.reload.status).to eq('failed')
    expect(message.external_error).to eq('file is too big media_too_large')
  end

  it 'leaves a failed message alone' do
    message.update!(status: :failed)

    expect(described_class.apply(message, 'delivered')).to be(false)
  end

  # Receipts arrive out of order, so a failure can land after the read that followed a
  # later retry. Letting it through would tell the agent a message the contact already
  # read never arrived.
  it 'does not fail a message the contact already read' do
    message.update!(status: :read)

    expect(described_class.apply(message, 'failed', error: 'boom')).to be(false)
    expect(message.reload.status).to eq('read')
    expect(message.external_error).to be_blank
  end

  it 'has nothing to say about a second failure' do
    message.update!(status: :failed, external_error: 'first')

    expect(described_class.apply(message, 'failed', error: 'second')).to be(false)
    expect(message.reload.external_error).to eq('first')
  end
end
