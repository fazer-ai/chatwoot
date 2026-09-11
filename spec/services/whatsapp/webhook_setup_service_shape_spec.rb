require 'rails_helper'

# The fence for #590. The defect was not one wrong line, it was a shape: a `rescue` that answers
# the decision with the same word the decision uses for "no", so a read that never happened and a
# read that said no become indistinguishable to the code that writes to Meta.
#
# The service now answers that question with named states and never with a bare boolean out of a
# rescue. This checks the shape, because the next one will be written by someone who has not read
# #590, and a review note is read once.
describe Whatsapp::WebhookSetupService do
  let(:source_path) { 'app/services/whatsapp/webhook_setup_service.rb' }
  let(:source) { Rails.root.join(source_path).read }

  # Everything from `rescue` to the `end` that closes its method, taken at the method's own
  # indentation so a rescue inside a block does not swallow the rest of the file.
  def rescue_bodies(text)
    text.scan(/^(\s*)rescue\s.*?\n(.*?)^\1end$/m).map { |indent, body| body.gsub(/^#{indent}\s*/, '') }
  end

  # The selection, named so the scanner's own examples can exercise it. Inline in the check below it
  # was unreachable by any arrangement, because the guarded file is clean and a blinded predicate and
  # a working one agree on a clean file.
  def boolean_rescues(text)
    rescue_bodies(text).select { |body| body.lines.map(&:strip).reject(&:empty?).last&.match?(/\A(true|false)\z/) }
  end

  it 'answers no decision with a bare boolean out of a rescue' do
    # `true` or `false` as the last thing a rescue produces. That is the whole defect: the caller
    # cannot tell it from an answer, and here the caller registers a phone number on it.
    expect(boolean_rescues(source)).to be_empty
  end

  it 'reads the rescues it is supposed to inspect, so an empty scan cannot pass as a clean one' do
    # Four today: the registration write, the webhook setup that re-raises, and the two reads that
    # answer `:unknown`. If this number changes, someone touched the error handling in this file and
    # should say which of the four they meant.
    expect(rescue_bodies(source).size).to eq(4)
  end

  it 'answers the two reads with the same vocabulary, so neither drifts back to a boolean' do
    # The health axis already defaulted the harmless way when it could not tell; the verification
    # axis defaulted the expensive way. They now say the same word for the same fact.
    expect(source.scan(/^\s*:unknown$/).size).to eq(2)
  end

  # The scanner is the fence, so it gets its own arrangements. A mutation that blinded it killed
  # nothing the first time this battery ran: the file it reads happens to be clean, so a broken
  # scanner and a working one agree on it.
  describe 'the scanner itself' do
    it 'flags a rescue that answers the decision with a bare boolean' do
      source = <<~RUBY
        def whatever
          read_something
        rescue StandardError => e
          Rails.logger.error(e.message)
          false
        end
      RUBY

      expect(boolean_rescues(source).size).to eq(1)
    end

    it 'reads a rescue to the end that closes its method, not to the first end it meets' do
      # A `while`, a block or a nested `if` inside a rescue body each close with their own `end`.
      # A scanner stopping at the first one would read a truncated body and miss what it answers.
      source = <<~RUBY
        def whatever
          read_something
        rescue StandardError => e
          [1, 2].each do |n|
            Rails.logger.error(n)
          end
          false
        end
      RUBY

      expect(boolean_rescues(source).size).to eq(1)
    end

    it 'flags the other bare boolean too, because the lazy fix is the opposite default' do
      # "Assume verified when the read fails" is the same defect pointing the other way: a number
      # that genuinely is not verified silently stops being registered (#590).
      source = <<~RUBY
        def whatever
          read_something
        rescue StandardError => e
          Rails.logger.error(e.message)
          true
        end
      RUBY

      expect(boolean_rescues(source).size).to eq(1)
    end

    it 'leaves a rescue that answers a named state alone' do
      source = <<~RUBY
        def whatever
          read_something
        rescue StandardError => e
          Rails.logger.error(e.message)
          :unknown
        end
      RUBY

      expect(rescue_bodies(source).size).to eq(1)
      expect(boolean_rescues(source)).to be_empty
    end
  end
end
