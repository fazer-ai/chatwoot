require 'rails_helper'

describe Whatsapp::GraphRequestOptions do
  # The two files that talk to Meta's Graph API. A call added to either of them without the ceiling
  # is the whole failure this fence exists for: the alternative was a line in a review checklist,
  # and a checklist is read once.
  let(:guarded_sources) do
    %w[
      app/services/whatsapp/facebook_api_client.rb
      app/services/whatsapp/health_service.rb
    ]
  end

  # Reads a call the way the parser would, not the way a line-oriented grep would: `HTTParty.get(`
  # opens a call that runs for several lines, and only the text up to its matching paren says
  # whether the options are in THIS call or in the next one further down the file.
  def graph_calls(source)
    calls = []
    source.to_enum(:scan, /HTTParty\.(?:get|post|put|patch|delete)\(/).each do
      start = Regexp.last_match.begin(0)
      depth = 0
      source[start..].each_char.with_index do |char, offset|
        depth += 1 if char == '('
        next unless char == ')'

        depth -= 1
        next unless depth.zero?

        calls << source[start, offset + 1]
        break
      end
    end
    calls
  end

  it 'reads a call to its own closing paren, not to the first one it meets' do
    # Every call in the guarded files happens to carry the options right after the URL, so a scanner
    # that stopped at the first `)` would still find them and this fence would pass for the wrong
    # reason. It would then report a false offender the day a call carries the options after an
    # argument that has parens of its own, which is what this arrangement is.
    source = <<~RUBY
      HTTParty.get(
        "\#{BASE_URI}/\#{@api_version}/x",
        query: { token: GlobalConfigService.load('A', '') },
        **GRAPH_REQUEST_OPTIONS
      )
    RUBY

    expect(graph_calls(source).first).to include('GRAPH_REQUEST_OPTIONS')
  end

  it 'caps the wait and the retry, because a ceiling alone still costs twice on a read' do
    expect(described_class::GRAPH_REQUEST_OPTIONS).to eq(timeout: 10, max_retries: 0)
  end

  it 'leaves no Graph call in the guarded files without the ceiling' do
    without_ceiling = guarded_sources.flat_map do |path|
      graph_calls(Rails.root.join(path).read)
        .reject { |call| call.include?('GRAPH_REQUEST_OPTIONS') }
        .map { |call| "#{path}: #{call.lines.first.strip} #{call.lines[1].to_s.strip}" }
    end

    expect(without_ceiling).to be_empty
  end

  it 'reads every call in the guarded files, so an empty result cannot pass as a clean one' do
    # The check above answers "nothing without a ceiling", and it answers that for zero calls too.
    # This one measures that the scan actually reached the calls it was supposed to inspect.
    counts = guarded_sources.index_with { |path| graph_calls(Rails.root.join(path).read).size }

    expect(counts).to eq(
      'app/services/whatsapp/facebook_api_client.rb' => 10,
      'app/services/whatsapp/health_service.rb' => 1
    )
  end
end
