require 'rails_helper'

describe Import::SilentWrite do
  it 'is off outside a wrap, which is the ordinary path and must go through untouched' do
    expect(described_class).not_to be_on
    expect(described_class).not_to be_archive
    expect(described_class).not_to be_announce
  end

  it 'writes an archive by default' do
    described_class.wrap do
      expect(described_class).to be_on
      expect(described_class).to be_archive
      expect(described_class).not_to be_announce
    end
  end

  it 'raises the level for the stretch somebody is watching' do
    described_class.wrap(announce: true) do
      expect(described_class).to be_on
      expect(described_class).not_to be_archive
      expect(described_class).to be_announce
    end
  end

  # The gap half of a run raises the level inside the enclosing archive wrap and has to
  # hand the archive level back on the way out.
  it 'restores the enclosing level rather than clearing it' do
    described_class.wrap do
      described_class.wrap(announce: true) { expect(described_class).to be_announce }
      expect(described_class).to be_archive
    end
    expect(described_class).not_to be_on
  end

  it 'clears the flag when the block raises' do
    expect { described_class.wrap { raise 'boom' } }.to raise_error('boom')
    expect(described_class).not_to be_on
  end
end
