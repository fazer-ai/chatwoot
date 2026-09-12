require 'rails_helper'

# rubocop:disable RSpec/DescribeClass -- the subject is eleven calls across eight unrelated
# services, and what they have in common is the number each one does not share.
#
# This file lives under `spec/enterprise`, which the CE suite deletes before it runs
# (`run_foss_spec.yml` does `rm -rf enterprise spec/enterprise`). So nothing here is
# covered by CI in this repo: it runs in the Pro repo, and locally. The fence below reads
# files from `enterprise/`, which is exactly why it cannot live in `spec/lib`.
RSpec.describe 'the ceilings of the enterprise integrations' do
  # Two calls to the same service with different numbers, because they wait on different
  # things: `crawl` registers a job and answers, `scrape` fetches the page first.
  it 'waits longer on a scrape than on registering a crawl' do
    expect(Captain::Tools::FirecrawlService::SCRAPE_REQUEST_OPTIONS[:timeout])
      .to be > Captain::Tools::FirecrawlService::CRAWL_REQUEST_OPTIONS[:timeout]
    expect(Captain::Tools::FirecrawlService::CRAWL_REQUEST_OPTIONS).to include(max_retries: 0)
    expect(Captain::Tools::FirecrawlService::SCRAPE_REQUEST_OPTIONS).to include(max_retries: 0)
  end

  # The one call in this tree that is a chat completion. The thinking time before the first
  # byte is the point of the call, so it gets the long ceiling, and `max_retries: 0` matters
  # here more than elsewhere because a repeat is a second answer and a second bill.
  it 'gives the model room to think, and never asks twice' do
    source = File.read(Rails.root.join('enterprise/app/models/enterprise/concerns/article.rb'))

    expect(source).to include('timeout: 120, max_retries: 0')
  end

  # A fence, not a checklist: every HTTParty call in the enterprise tree carries both axes.
  #
  # Parsed rather than grepped, because four of these calls carry their options as
  # `**GRAPH_REQUEST_OPTIONS` and a count of the word `timeout:` reads those as bare. That
  # is the same mistake in miniature that this whole sweep exists to undo: counting the
  # text instead of reading the call.
  it 'leaves no call in the enterprise tree without both axes' do
    require 'prism'

    constants = {}
    sources = Dir.glob(Rails.root.join('{app,lib,enterprise}/**/*.rb'))
    sources.each do |path|
      File.read(path).scan(/^\s*([A-Z][A-Z0-9_]*)\s*=\s*(\{.*?\})\.freeze/m) do |name, literal|
        constants[name] = { timeout: literal.include?('timeout'), retries: literal.include?('max_retries') }
      end
    end

    bare = []
    Dir.glob(Rails.root.join('enterprise/**/*.rb')).each do |path|
      body = File.read(path)
      next unless body.include?('HTTParty')

      stack = [Prism.parse(body).value]
      until stack.empty?
        node = stack.pop
        stack.concat(node.compact_child_nodes)
        next unless node.is_a?(Prism::CallNode)
        next unless node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :HTTParty

        text = (node.arguments&.arguments || []).map { |arg| body.byteslice(arg.location.start_offset, arg.location.length) }.join(', ')
        timeout = text.include?('timeout')
        retries = text.include?('max_retries')
        text.scan(/\*\*(?:[A-Z][A-Za-z0-9_]*::)*([A-Z][A-Z0-9_]*)/).flatten.each do |name|
          next unless constants[name]

          timeout ||= constants[name][:timeout]
          retries ||= constants[name][:retries]
        end
        bare << "#{Pathname.new(path).relative_path_from(Rails.root)}:#{node.location.start_line}" unless timeout && retries
      end
    end

    expect(bare).to be_empty
  end
end
# rubocop:enable RSpec/DescribeClass
