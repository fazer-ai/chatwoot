require 'rails_helper'

RSpec.describe Release::CatalogService do
  let(:tmp_path) { Rails.root.join('tmp/release_notes_test.yml') }

  before do
    described_class.reset_cache!
    stub_const('Release::CatalogService::CONFIG_PATH', tmp_path)
  end

  after do
    FileUtils.rm_f(tmp_path)
    described_class.reset_cache!
  end

  describe '.all' do
    it 'returns an empty array when the file is missing' do
      FileUtils.rm_f(tmp_path)
      expect(described_class.all).to eq([])
    end

    it 'returns the parsed entries' do
      File.write(tmp_path, [{ 'tag' => 'v1.0.0', 'notes' => { 'en' => 'hi' } }].to_yaml)
      expect(described_class.all.first['tag']).to eq('v1.0.0')
    end

    it 'gracefully handles malformed yaml' do
      File.write(tmp_path, 'not: valid: yaml: at: all')
      expect(described_class.all).to eq([])
    end
  end

  describe '.latest' do
    it 'is the first entry in the catalog' do
      File.write(tmp_path, [
        { 'tag' => 'v2.0.0' },
        { 'tag' => 'v1.0.0' }
      ].to_yaml)
      expect(described_class.latest['tag']).to eq('v2.0.0')
    end

    it 'is nil when the catalog is empty' do
      File.write(tmp_path, [].to_yaml)
      expect(described_class.latest).to be_nil
    end
  end
end
