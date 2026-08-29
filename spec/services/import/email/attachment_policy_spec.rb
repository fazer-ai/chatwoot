require 'rails_helper'

describe Import::Email::AttachmentPolicy do
  describe '.build' do
    it 'reads a missing value as none, which is the documented default' do
      expect(described_class.build(nil)).to be_none
      expect(described_class.build('')).to be_none
    end

    it 'reads the two spelled-out states' do
      expect(described_class.build('all')).to be_all
      expect(described_class.build(:all)).to be_all
      expect(described_class.build('none')).to be_none
    end

    it 'reads a time as a cutoff' do
      policy = described_class.build(Time.zone.parse('2024-01-01'))
      expect(policy).not_to be_all
      expect(policy).not_to be_none
    end

    it 'refuses a value it cannot read rather than falling back' do
      expect { described_class.build('sim') }.to raise_error(ArgumentError, /must be :none, :all or a time/)
    end
  end

  describe '#skip?' do
    it 'skips everything by default, so a first pass costs no attachment bytes' do
      policy = described_class.build(nil)
      expect(policy.skip?(Time.zone.parse('2025-06-01'))).to be(true)
      expect(policy.skip?(nil)).to be(true)
    end

    it 'skips nothing when told to take them all' do
      policy = described_class.build('all')
      expect(policy.skip?(Time.zone.parse('2020-01-01'))).to be(false)
      expect(policy.skip?(nil)).to be(false)
    end

    it 'takes what is newer than the cutoff and leaves what is older' do
      policy = described_class.build(Time.zone.parse('2024-01-01'))
      expect(policy.skip?(Time.zone.parse('2023-06-01'))).to be(true)
      expect(policy.skip?(Time.zone.parse('2025-06-01'))).to be(false)
    end

    it 'treats an unknown date as out of scope under a cutoff' do
      expect(described_class.build(Time.zone.parse('2024-01-01')).skip?(nil)).to be(true)
    end
  end
end
