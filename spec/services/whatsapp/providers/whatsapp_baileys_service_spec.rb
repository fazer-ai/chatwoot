require 'rails_helper'

describe Whatsapp::Providers::WhatsappBaileysService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) { create(:channel_whatsapp, provider: 'baileys') }
  let(:message) { create(:message) }

  let(:test_send_phone_number) { '+5511987654321' }

  describe '#setup_channel_provider' do
    context 'when called' do
      it 'calls the connection endpoint' do
        with_modified_env DEFAULT_BAILEYS_BASE_URL: 'http://test.com' do
          stub_request(:post, "http://test.com/connections/#{whatsapp_channel.phone_number}")
            .with(
              headers: { 'Content-Type' => 'application/json', 'x-api-key' => whatsapp_channel.provider_config['api_key'] },
              body: {
                clientName: 'Chatwoot',
                webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
                webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token']
              }.to_json
            )
            .to_return(status: 200)

          response = service.setup_channel_provider
          expect(response).to be true
        end
      end
    end
  end

  describe '#disconnect_channel_provider' do
    context 'when called' do
      it 'disconnects the whatsapp connection' do
        with_modified_env DEFAULT_BAILEYS_BASE_URL: 'http://test.com' do
          stub_request(:delete, "http://test.com/connections/#{whatsapp_channel.phone_number}")
            .with(headers: { 'Content-Type' => 'application/json', 'x-api-key' => whatsapp_channel.provider_config['api_key'] })
            .to_return(status: 200)

          response = service.disconnect_channel_provider
          expect(response).to be true
        end
      end
    end
  end

  describe '#send_message' do
    context 'when response is successful' do
      it 'returns the message id' do
        with_modified_env DEFAULT_BAILEYS_BASE_URL: 'http://test.com' do
          stub_request(:post, "http://test.com/connections/#{whatsapp_channel.phone_number}/send-message")
            .with(
              headers: { 'Content-Type' => 'application/json', 'x-api-key' => whatsapp_channel.provider_config['api_key'] },
              body: {
                type: 'text',
                to: test_send_phone_number,
                text: { body: message.content }
              }.to_json
            )
            .to_return(
              status: 200,
              body: { 'key' => { 'id' => message.id } }.to_json
            )

          result = service.send_message(test_send_phone_number, message)
          expect(result).to be(true)
        end
      end
    end

    context 'when response is unsuccessful' do
      it 'logs the error and returns nil' do
        with_modified_env DEFAULT_BAILEYS_BASE_URL: 'http://test.com' do
          stub_request(:post, "http://test.com/connections/#{whatsapp_channel.phone_number}/send-message")
            .with(
              headers: { 'Content-Type' => 'application/json', 'x-api-key' => whatsapp_channel.provider_config['api_key'] },
              body: {
                type: 'text',
                to: test_send_phone_number,
                text: { body: message.content }
              }.to_json
            )
            .to_return(
              status: 400,
              body: 'error message',
              headers: {}
            )

          expect(Rails.logger).to receive(:error).with('error message')

          result = service.send_message(test_send_phone_number, message)
          expect(result).to be(false)
        end
      end
    end
  end

  describe '#api_headers' do
    context 'when called' do
      it 'returns the headers' do
        expect(service.send(:api_headers)).to eq('x-api-key' => 'test_key', 'Content-Type' => 'application/json')
      end
    end
  end

  # describe '#send_message' do
  #   context 'when called' do
  #     it 'calls message endpoints for text messages' do
  #       message = create(:message, message_type: :outgoing, content: 'test', inbox: whatsapp_channel.inbox)

  #       stub_request(:post, "#{ENV.fetch('BAILEYS_BASE_URL', 'http://localhost:3025')}/send/#{whatsapp_channel.phone_number}")
  #         .with(
  #           body: {
  #             type: 'text',
  #             text: { body: message.content }
  #           }.to_json,
  #           headers: { 'Content-Type' => 'application/json', 'x-api-key' => whatsapp_channel.provider_config['api_key'] }
  #         )
  #         .to_return(status: 200, body: whatsapp_response.to_json, headers: response_headers)

  #       expect(service.send_message(whatsapp_channel.phone_number, message)).to eq 'message_id'
  #     end
  #   end
  # end

  describe 'Ability to configure Base URL' do
    context 'when environment variable DEFAULT_BAILEYS_BASE_URL is not set' do
      it 'uses the default base url' do
        expect(service.send(:api_base_path)).to eq('http://localhost:3025')
      end
    end

    context 'when environment variable DEFAULT_BAILEYS_BASE_URL is set' do
      it 'uses the base url from the environment variable' do
        with_modified_env DEFAULT_BAILEYS_BASE_URL: 'http://test.com' do
          expect(service.send(:api_base_path)).to eq('http://test.com')
        end
      end
    end
  end

  describe 'Ability to configure Client Name' do
    context 'when environment variable DEFAULT_BAILEYS_CLIENT_NAME is not set' do
      it 'uses the default client name' do
        expect(service.send(:client_name)).to eq('Chatwoot')
      end
    end

    context 'when environment variable DEFAULT_BAILEYS_CLIENT_NAME is set' do
      it 'uses the client name from the environment variable' do
        with_modified_env DEFAULT_BAILEYS_CLIENT_NAME: 'Test Client' do
          expect(service.send(:client_name)).to eq('Test Client')
        end
      end
    end
  end
end
