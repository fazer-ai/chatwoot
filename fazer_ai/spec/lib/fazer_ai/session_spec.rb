# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Session do
  before do
    described_class.reset!
  end

  describe '.session_id' do
    it 'generates a UUID' do
      session_id = described_class.session_id

      expect(session_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'returns the same session ID on subsequent calls' do
      first_call = described_class.session_id
      second_call = described_class.session_id

      expect(second_call).to eq(first_call)
    end
  end

  describe '.reset!' do
    it 'clears the cached session ID' do
      original_id = described_class.session_id

      described_class.reset!
      new_id = described_class.session_id

      expect(new_id).not_to eq(original_id)
    end
  end
end
