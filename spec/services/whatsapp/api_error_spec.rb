require 'rails_helper'

describe Whatsapp::ApiError do
  # Meta's own shape: the code lives in `error.code`, and the subcode, when there is one, in
  # `error.error_subcode`.
  let(:refusal) do
    instance_double(
      HTTParty::Response,
      code: 401,
      parsed_response: { 'error' => { 'message' => 'Error validating access token', 'type' => 'OAuthException',
                                      'code' => 190, 'error_subcode' => 463 } }
    )
  end

  describe '.from_response' do
    it "speaks Meta's message when the caller has nothing to add" do
      error = described_class.from_response(refusal)

      expect(error.message).to eq('Error validating access token')
      expect([error.http_status, error.code, error.subcode]).to eq([401, 190, 463])
    end

    it 'keeps the code when the caller prefixes the step that failed' do
      error = described_class.from_response(refusal, message: 'App subscription to WABA failed: {...}')

      expect(error.message).to eq('App subscription to WABA failed: {...}')
      expect(error).to be_authorization_error
    end

    # Something in front of Meta answering with an HTML page. It is still a failure, and it is still
    # not an answer about the credentials.
    it 'leaves the code nil when the body is not the shape Meta documents' do
      response = instance_double(HTTParty::Response, code: 502, parsed_response: '<html>502 Bad Gateway</html>')

      error = described_class.from_response(response)

      expect(error.message).to eq('WhatsApp API request failed')
      expect(error.code).to be_nil
      expect(error).not_to be_authorization_error
    end
  end

  describe '#authorization_error?' do
    it 'is true only for the code that talks about the credentials' do
      expect(described_class.new(message: 'x', http_status: 401, code: 190)).to be_authorization_error
    end

    it 'is false for a refusal of this particular request' do
      expect(described_class.new(message: 'x', http_status: 403, code: 200)).not_to be_authorization_error
    end

    it 'reads a code that arrived as a string, which is what the cast is there for' do
      expect(described_class.new(message: 'x', http_status: 401, code: '190')).to be_authorization_error
    end

    it 'is false when there is no code at all, which is what silence leaves behind' do
      expect(described_class.new(message: 'x', http_status: 500)).not_to be_authorization_error
    end
  end

  # The health card asks the same question through its own name, and it has to keep getting the same
  # answer: `Whatsapp::HealthService::ApiError` exists so `rescue` reads as "the health read failed",
  # not so it can decide on its own what 190 means.
  describe Whatsapp::HealthService::ApiError do
    it 'is this error under another name' do
      expect(described_class.new(message: 'x', http_status: 401, code: 190)).to be_authorization_error
    end
  end

  describe 'the one place the question is asked' do
    # A second `def authorization_error?`, or a second literal 190, is the failure this guards: the
    # two copies agree on the day they are written and drift the first time Meta adds a code. The
    # scan is over the WhatsApp tree, which is where the question belongs.
    def askers(pattern, sources)
      sources.select { |path| Rails.root.join(path).read.match?(pattern) }
    end

    let(:sources) do
      Dir.glob(Rails.root.join('app/{services/whatsapp,models/channel}/**/*.rb'))
         .map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s }
    end

    it 'scans files that exist, so an empty result cannot pass as a clean one' do
      expect(sources).to include('app/services/whatsapp/api_error.rb', 'app/models/channel/whatsapp.rb')
    end

    it 'finds what it is looking for when it is there' do
      # Against the guarded tree the scan is expected to answer "one file", and it would answer the
      # same for a pattern that matches nothing at all. This pins the scan to a pattern that does.
      expect(askers(/AUTHORIZATION_ERROR_CODE/, sources)).to eq(['app/services/whatsapp/api_error.rb'])
    end

    it 'has one definition of the question' do
      expect(askers(/def authorization_error\?/, sources)).to eq(['app/services/whatsapp/api_error.rb'])
    end

    it 'has one place that knows the number' do
      expect(askers(/\b190\b/, sources)).to eq(['app/services/whatsapp/api_error.rb'])
    end
  end
end
