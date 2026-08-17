require 'rails_helper'

# The catalog's value objects validate their enums by coercing to a string first. That
# coercion has to reach the stored value, not only the check: a constructor that
# accepted `:open` and then stored the symbol would make every predicate on it false and
# put a non-canonical value on the wire, and it would do so silently.
RSpec.describe Whatsapp::Session::Model do
  let(:model) { described_class }

  it 'stores a symbol connection as the canonical string' do
    state = model::ConnectionState.new(connection: :open)

    expect(state.connection).to eq('open')
    expect(state).to be_open
    expect(state.to_h['connection']).to eq('open')
  end

  it 'stores a symbol pairing mode as the canonical string' do
    expect(model::Commands::SessionConnect.new(pairing: :qr).pairing).to eq('qr')
  end

  it 'stores a symbol media kind as the canonical string' do
    media = model::Content::Media.new(kind: :image, mime: 'image/jpeg')

    expect(media.kind).to eq('image')
    expect(media.attachment_file_type).to eq(:image)
  end

  it 'stores a symbol media ref kind as the canonical string' do
    expect(model::MediaRef.new(kind: :url, url: 'https://example.test/a.jpg').kind).to eq('url')
  end

  it 'stores a symbol attachment kind, and falls back to the declared default' do
    expect(model::Attachment.new(kind: :audio, url: 'https://example.test/a.ogg').kind).to eq('audio')
    expect(model::Attachment.new(url: 'https://example.test/a.pdf').kind).to eq('document')
  end

  it 'still refuses a value outside the enum, symbol or not' do
    expect { model::ConnectionState.new(connection: :sideways) }
      .to raise_error(Whatsapp::Session::Errors::InvalidPayload)
  end
end
