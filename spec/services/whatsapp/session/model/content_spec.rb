require 'rails_helper'

RSpec.describe Whatsapp::Session::Model::Content do
  it 'builds the right class from the payload type' do
    expect(described_class.from_h({ 'type' => 'text', 'body' => 'oi' })).to be_a(described_class::Text)
    expect(described_class.from_h({ 'type' => 'location', 'latitude' => 1.0, 'longitude' => 2.0 }))
      .to be_a(described_class::Location)
  end

  it 'keeps the type inside the payload so a message round-trips' do
    content = described_class::Text.new(body: 'oi')

    expect(content.to_h).to eq({ 'body' => 'oi', 'type' => 'text' })
  end

  it 'refuses an unknown content type' do
    expect { described_class.from_h({ 'type' => 'hologram' }) }.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
  end

  describe described_class::Media do
    it 'maps the whatsapp media kind to the chatwoot attachment type' do
      expect(described_class.new(kind: 'sticker').attachment_file_type).to eq(:image)
      expect(described_class.new(kind: 'audio', voice_note: true).attachment_file_type).to eq(:audio)
      expect(described_class.new(kind: 'document').attachment_file_type).to eq(:file)
    end

    it 'refuses an unknown media kind' do
      expect { described_class.new(kind: 'hologram') }.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
    end
  end

  describe described_class::Reaction do
    it 'treats an empty emoji as a removal' do
      expect(described_class.new(target_id: '3EB0', emoji: '')).to be_removal
      expect(described_class.new(target_id: '3EB0', emoji: '👍')).not_to be_removal
    end
  end
end
