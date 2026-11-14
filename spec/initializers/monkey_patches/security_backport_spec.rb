require 'rails_helper'

RSpec.describe SecurityBackport do
  let(:ignored) { YAML.load_file(Rails.root.join('.bundler-audit.yml')).fetch('ignore') }

  it 'has the backports in config/initializers/monkey_patches registered' do
    expect(described_class.entries.map(&:advisory)).to include('GHSA-v924-7rp8-4mxh', 'GHSA-8474-xrp6-wh69')
  end

  # When this fails the installed gem already ships the fix: delete the backport, its spec and
  # its .bundler-audit.yml entry, instead of keeping a copy that overrides upstream's code.
  described_class.entries.each do |entry|
    it "still needs the #{entry.advisory} backport for #{entry.gem_name} below #{entry.fixed_in}" do
      expect(entry).to be_needed,
                       "#{entry.gem_name} #{entry.installed_version} ships the fix for #{entry.advisory}: remove the backport and its ignore"
    end

    it "keeps #{entry.advisory} in .bundler-audit.yml while the backport covers it" do
      expect(ignored).to include(entry.advisory)
    end
  end

  describe '.register' do
    it 'answers whether the backport still applies, by the installed version of the gem' do
      installed = Gem.loaded_specs.fetch('activesupport').version

      expect(described_class.register(advisory: 'GHSA-test-new', gem_name: 'activesupport', fixed_in: installed.bump.to_s)).to be(true)
      expect(described_class.register(advisory: 'GHSA-test-old', gem_name: 'activesupport', fixed_in: installed.to_s)).to be(false)
    ensure
      described_class.entries.reject! { |entry| entry.advisory.start_with?('GHSA-test-') }
    end
  end
end
