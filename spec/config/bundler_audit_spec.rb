require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
describe 'Ignored bundler-audit advisories' do
  # rubocop:enable RSpec/DescribeClass
  let(:ignored) { YAML.load_file(Rails.root.join('.bundler-audit.yml')).fetch('ignore', []) }
  let(:rack_proxy) { Bundler::LockfileParser.new(Rails.root.join('Gemfile.lock').read).specs.find { |spec| spec.name == 'rack-proxy' } }

  # GHSA-42qh-8mx8-7wqm is framing in rack-proxy 1.0.0 to 1.0.2, and the advisory database
  # lists no unaffected range, so the scan flags the 0.x vite_ruby pins us to. Ignored
  # because the only proxy here is the Vite dev server's, in development, to our own Vite.
  it 'does not fail the security scan on the rack-proxy framing advisory' do
    expect(ignored).to include('GHSA-42qh-8mx8-7wqm')
  end

  # An ignore holds for every version of the gem, so a rack-proxy that reaches the 1.x
  # the advisory is about would pass the scan in silence. This is what turns it red again.
  it 'keeps that ignore tied to the 0.x rack-proxy it was written for' do
    tied = ignored.exclude?('GHSA-42qh-8mx8-7wqm') || rack_proxy.version < Gem::Version.new('1.0.0')

    expect(tied).to be(true), "rack-proxy #{rack_proxy.version} is in the range GHSA-42qh-8mx8-7wqm is about; drop the ignore"
  end
end
