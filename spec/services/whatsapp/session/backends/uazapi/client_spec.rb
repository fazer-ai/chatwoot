require 'rails_helper'

RSpec.describe Whatsapp::Session::Backends::Uazapi::Client do
  subject(:client) { described_class.new(base_url: 'https://uazapi.test/', token: 'instance-token') }

  let(:errors) { Whatsapp::Session::Errors }

  it 'refuses to exist without somewhere to go and something to say' do
    expect { described_class.new(base_url: '', token: 'x') }.to raise_error(errors::InvalidConfig)
    expect { described_class.new(base_url: 'https://uazapi.test', token: '') }.to raise_error(errors::InvalidConfig)
  end

  it 'authenticates with the instance token and trims a trailing slash off the base url' do
    stub_request(:post, 'https://uazapi.test/send/text').to_return(status: 200, body: '{"messageid":"3EB0"}')

    expect(client.post('/send/text', { number: '55' })).to eq('messageid' => '3EB0')
    expect(WebMock).to have_requested(:post, 'https://uazapi.test/send/text').with(headers: { 'token' => 'instance-token' })
  end

  describe 'what it makes of a failure' do
    # The class decides what the caller does next: a retryable error keeps an outbound
    # message in the queue, a non-retryable one puts the reason in front of the agent.
    {
      400 => 'Whatsapp::Session::Errors::InvalidPayload',
      401 => 'Whatsapp::Session::Errors::Unauthorized',
      403 => 'Whatsapp::Session::Errors::Unauthorized',
      404 => 'Whatsapp::Session::Errors::SessionNotFound',
      405 => 'Whatsapp::Session::Errors::NotSupported',
      413 => 'Whatsapp::Session::Errors::MediaTooLarge',
      429 => 'Whatsapp::Session::Errors::RateLimited',
      500 => 'Whatsapp::Session::Errors::ProviderUnavailable',
      503 => 'Whatsapp::Session::Errors::ProviderUnavailable'
    }.each do |status, error|
      it "answers #{status} with #{error.demodulize}" do
        stub_request(:get, 'https://uazapi.test/instance/status').to_return(status: status, body: '{}')

        expect { client.get('/instance/status') }.to(raise_error { |raised| expect(raised.class.name).to eq(error) })
      end
    end

    # An unmapped 4xx is this request being wrong, and retrying it would keep a message in
    # the queue forever instead of telling the agent it failed.
    it 'treats an unmapped 4xx as a request that will not work next time either' do
      stub_request(:get, 'https://uazapi.test/instance/status').to_return(status: 409, body: '{}')

      expect { client.get('/instance/status') }.to(raise_error { |raised| expect(raised).not_to be_retryable })
    end

    it 'quotes the provider message and nothing else from the body' do
      stub_request(:get, 'https://uazapi.test/instance/status')
        .to_return(status: 405, body: { message: 'Method Not Allowed.', data: { token: 'instance-token' } }.to_json)

      expect { client.get('/instance/status') }.to raise_error(errors::NotSupported, /Method Not Allowed/) do |raised|
        expect(raised.message).not_to include('instance-token')
      end
    end

    it 'reports a provider that does not answer as one to ask again later' do
      stub_request(:get, 'https://uazapi.test/instance/status').to_timeout

      expect { client.get('/instance/status') }.to raise_error(errors::ProviderUnavailable) do |raised|
        expect(raised).to be_retryable
      end
    end
  end
end
