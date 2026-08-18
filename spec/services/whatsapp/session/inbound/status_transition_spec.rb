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
end
