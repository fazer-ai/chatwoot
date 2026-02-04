require 'rails_helper'

describe GlobalConfig do
  subject(:trigger) { described_class }

  describe 'execute' do
    context 'when called with default options' do
      before do
        described_class.clear_cache
      end

      it 'hit DB for the first call' do
        expect(InstallationConfig).to receive(:find_by)
        described_class.get('test')
      end

      it 'get from cache for subsequent calls' do
        # this loads from DB
        described_class.get('test')

        # subsequent calls should not hit DB
        expect(InstallationConfig).not_to receive(:find_by)
        described_class.get('test')
      end

      it 'clears cache and fetch from DB next time, when clear_cache is called' do
        # this loads from DB and is cached
        described_class.get('test')

        # clears the cache
        described_class.clear_cache

        # should be loaded from DB
        expect(InstallationConfig).to receive(:find_by).with({ name: 'test' }).and_return(nil)
        described_class.get('test')
      end
    end

    context 'when branding config is set via ENV' do
      before do
        described_class.clear_cache
      end

      it 'returns ENV value for branding config when different from default' do
        with_modified_env(BRAND_NAME: 'CustomBrand') do
          described_class.clear_cache
          expect(described_class.get_value('BRAND_NAME')).to eq('CustomBrand')
        end
      end

      it 'returns DB value when ENV value matches default' do
        create(:installation_config, name: 'BRAND_NAME', value: 'DBBrand')

        with_modified_env(BRAND_NAME: 'Chatwoot') do
          described_class.clear_cache
          expect(described_class.get_value('BRAND_NAME')).to eq('DBBrand')
        end
      end

      it 'handles boolean branding config from ENV' do
        with_modified_env(DISPLAY_MANIFEST: 'false') do
          described_class.clear_cache
          expect(described_class.get_value('DISPLAY_MANIFEST')).to be(false)
        end
      end

      it 'returns DB value for non-branding config even if ENV is set' do
        create(:installation_config, name: 'SOME_OTHER_CONFIG', value: 'db_value')

        with_modified_env(SOME_OTHER_CONFIG: 'env_value') do
          described_class.clear_cache
          expect(described_class.get_value('SOME_OTHER_CONFIG')).to eq('db_value')
        end
      end
    end
  end
end
