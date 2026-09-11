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

  it 'answers no decision with a bare boolean out of a rescue' do
    # `true` or `false` as the last thing a rescue produces. That is the whole defect: the caller
    # cannot tell it from an answer, and here the caller registers a phone number on it.
    booleans = rescue_bodies(source).select { |body| body.lines.map(&:strip).reject(&:empty?).last&.match?(/\A(true|false)\z/) }

    expect(booleans).to be_empty
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
end
