# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::Limits do
  describe '.unlimited?' do
    it 'returns false in CE' do
      expect(described_class.unlimited?).to be false
    end
  end

  describe '.polls_enabled?' do
    it 'returns false in CE' do
      expect(described_class.polls_enabled?).to be false
    end
  end

  describe '.max_private_channels' do
    it 'returns 2 in CE' do
      expect(described_class.max_private_channels).to eq(2)
    end
  end

  describe '.search_history_days' do
    it 'returns 90 in CE' do
      expect(described_class.search_history_days).to eq(90)
    end
  end
end
