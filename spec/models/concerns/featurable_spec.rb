# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Featurable do
  describe '.feature_flag_value' do
    it 'returns 0 for unknown features' do
      expect(described_class.feature_flag_value('nonexistent_feature')).to eq(0)
    end

    it 'returns the unsigned bit value for low-position features' do
      first_feature = described_class::FEATURE_LIST.first['name']
      expect(described_class.feature_flag_value(first_feature)).to eq(1)
    end

    it 'returns the signed two\'s complement representation for high-position features' do
      stub_const(
        "#{described_class}::FEATURE_LIST",
        Array.new(64) { |i| { 'name' => "feature_#{i}" } }.freeze
      )

      # Position 64 (0-indexed 63) is the sign bit on signed bigint.
      expect(described_class.feature_flag_value('feature_63')).to eq(-(1 << 63))
      # Lower positions stay positive.
      expect(described_class.feature_flag_value('feature_62')).to eq(1 << 62)
    end
  end
end
