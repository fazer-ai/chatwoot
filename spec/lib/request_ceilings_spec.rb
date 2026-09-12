require 'rails_helper'

# The one-off integrations of #589: four third parties that share no client and no
# semantics, so each carries its own number. Grouped here because what they have in
# common is the absence, not the value.
#
# Each example goes through the real call and reads the options that went out. Counting
# the constant in the source proves the text is there, not that it resolves, and both
# things this sweep has broken so far were resolution and not text.
# rubocop:disable RSpec/DescribeClass -- there is no class here on purpose: the subject is
# four unrelated integrations and the numbers they do not share.
RSpec.describe 'the ceilings of the one-off integrations' do
  # hCaptcha sits in front of signup and login, so the person is looking at a form that
  # has not answered. Five seconds is already generous for checking a token.
  it 'keeps the captcha check short, because a person is waiting on a form' do
    options = nil
    allow(HTTParty).to receive(:post) do |_url, **kwargs|
      options = kwargs
      instance_double(HTTParty::Response, success?: true, parsed_response: { 'success' => true })
    end
    allow(GlobalConfigService).to receive(:load).with('HCAPTCHA_SERVER_KEY', '').and_return('a-key')

    ChatwootCaptcha.new('a-response').valid?

    expect(options).to include(timeout: 5, max_retries: 0)
  end

  # The opposite end of the same sweep. On the other side of this one an assistant is
  # composing an answer, so the thinking time before the first byte is the point of the
  # call and not a symptom: a short ceiling here would not save a worker, it would turn
  # every slow answer into no answer.
  it 'gives the assistant room to think, unlike every other ceiling here' do
    expect(Integrations::Captain::ProcessorService::CAPTAIN_REQUEST_OPTIONS)
      .to eq(timeout: 120, max_retries: 0)
    expect(Integrations::Captain::ProcessorService::CAPTAIN_REQUEST_OPTIONS[:timeout])
      .to be > ChatwootCaptcha::HCAPTCHA_REQUEST_OPTIONS[:timeout]
  end

  # An agent clicked a button and is waiting on the room to exist.
  it 'keeps the video room calls short' do
    options = nil
    allow(HTTParty).to receive(:get) do |_url, **kwargs|
      options = kwargs
      instance_double(HTTParty::Response, success?: true, parsed_response: {}, code: 200)
    end

    Dyte.new('acc', 'app', 'token').send(:get, 'presets')

    expect(options).to include(timeout: 10, max_retries: 0)
  end

  # The SMS send is the long one of this group, and for the same reason the WhatsApp and
  # Telegram sends are: an outgoing message carries `media` as URLs pointing back at us,
  # and Bandwidth fetches those before it answers. The credential check sends no body and
  # is answered out of Bandwidth's own state, so it gets the short one.
  it 'waits longer on a send than on a credential check, because one hands over a URL' do
    expect(Channel::Sms::BANDWIDTH_SEND_OPTIONS[:timeout])
      .to be > Channel::Sms::BANDWIDTH_REQUEST_OPTIONS[:timeout]
    expect(Channel::Sms::BANDWIDTH_SEND_OPTIONS).to include(max_retries: 0)
    expect(Channel::Sms::BANDWIDTH_REQUEST_OPTIONS).to include(max_retries: 0)
  end
end
# rubocop:enable RSpec/DescribeClass
