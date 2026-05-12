require 'rails_helper'

RSpec.describe Language do
  describe 'validations' do
    subject { build(:language) }

    it { is_expected.to validate_presence_of(:code) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:code) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:contacts).dependent(:nullify) }
  end

  describe '.ordered' do
    it 'orders by position then id' do
      described_class.delete_all
      third = create(:language, position: 3)
      first = create(:language, position: 1)
      second = create(:language, position: 2)

      expect(described_class.ordered.pluck(:id)).to eq([first.id, second.id, third.id])
    end
  end
end
