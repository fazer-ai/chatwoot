require 'pathname'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  def with_modified_env(options, &)
    ClimateControl.modify(options, &)
  end
end

fazer_ai_spec_root = Pathname.new(__dir__).join('..', 'fazer_ai', 'spec')
explicit_targets_requested = ARGV.any? do |arg|
  next false if arg.start_with?('-')

  path = arg.sub(/:\d+$/, '')
  File.exist?(path)
end

Dir[fazer_ai_spec_root.join('**', '*_spec.rb')].each { |path| require path } if fazer_ai_spec_root.exist? && !explicit_targets_requested
