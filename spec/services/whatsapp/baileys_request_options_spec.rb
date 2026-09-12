require 'rails_helper'

describe Whatsapp::BaileysRequestOptions do
  # One file, and the fence is here rather than folded into the Graph one because the number is
  # not the same and the reason for it is not the same: Meta is somebody else's API with no
  # published deadline, and the Baileys API is ours, with its own cuts written in its own config.
  let(:guarded_source) { 'app/services/whatsapp/providers/whatsapp_baileys_service.rb' }
  let(:source) { Rails.root.join(guarded_source).read }
  let(:calls) { provider_calls(source) }

  # Reads a call to its own closing paren rather than to the first one it meets: `HTTParty.post(`
  # opens a call that runs for a dozen lines here, and the body hash has parens of its own.
  def provider_calls(source)
    calls = []
    source.to_enum(:scan, /HTTParty\.(?:get|post|put|patch|delete|head)\(/).each do
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
    # Without this the scanner would stop inside `{ jid: jid }` and report the call as having no
    # ceiling, or worse, would find the ceiling of the call below and pass for the wrong reason.
    sample = <<~RUBY
      HTTParty.post(
        url,
        body: { jid: jid, keys: messages.map { |m| key_for(m) } }.to_json,
        **BAILEYS_REQUEST_OPTIONS
      )
    RUBY

    expect(provider_calls(sample).first).to include('BAILEYS_REQUEST_OPTIONS')
  end

  it 'caps the wait and the retry, because a ceiling alone still costs twice on a read' do
    expect(described_class::BAILEYS_REQUEST_OPTIONS).to eq(timeout: 90, max_retries: 0)
    expect(described_class::BAILEYS_SHORT_REQUEST_OPTIONS).to eq(timeout: 10, max_retries: 0)
  end

  it 'keeps the default above the cut the provider applies to itself' do
    # 75s is PROXY_REQUEST_TIMEOUT_MS in fazer-ai/baileys-api. A ceiling at or below it is a
    # ceiling that hangs up on a provider that was about to answer for itself, which on a write
    # means reporting a failure for something that happened.
    expect(described_class::BAILEYS_REQUEST_OPTIONS[:timeout]).to be > 75
  end

  it 'leaves no call to the provider without one of the two ceilings' do
    unguarded = calls.reject { |call| call.include?('BAILEYS_REQUEST_OPTIONS') || call.include?('BAILEYS_SHORT_REQUEST_OPTIONS') }

    expect(unguarded.map { |call| call.lines.first(2).map(&:strip).join(' ') }).to be_empty
  end

  it 'refuses a call that names both ceilings, because then neither is the one in force' do
    both = calls.select { |call| call.include?('**BAILEYS_REQUEST_OPTIONS') && call.include?('BAILEYS_SHORT_REQUEST_OPTIONS') }

    expect(both).to be_empty
  end

  it 'leaves no inline timeout beside the constant, which would be the value actually in force' do
    # A `timeout:` written after the splat wins over it, so the fence would read as satisfied
    # while the call ran on a number nobody wrote down.
    inline = calls.grep(/timeout:\s*\d/)

    expect(inline).to be_empty
  end

  it 'reads every call in the file, so an empty result cannot pass as a clean one' do
    # The checks above all answer "none", and they answer "none" for zero calls too. This is the
    # canary: it fails the day the scanner stops seeing the file, instead of reporting it clean.
    expect(calls.size).to eq(34)
  end

  # The split is the substance of this fence, not a detail: the short ceiling is the one that
  # gives up before the provider does, so a call moving into it silently is a call that starts
  # reporting failure on something the provider would have answered. Counting each side means a
  # move has to be made on purpose.
  it 'keeps the short ceiling on the calls that chose to give up before the provider does' do
    short = calls.count { |call| call.include?('BAILEYS_SHORT_REQUEST_OPTIONS') }

    expect(short).to eq(7)
  end

  it 'is the only source of a ceiling for this file' do
    # The constants live in a module of their own so that the value and its reasoning sit in one
    # place; a copy of the numbers in the service would be the thing that drifts.
    expect(source).to include('include Whatsapp::BaileysRequestOptions')
  end
end
