require 'rails_helper'

RSpec.describe Whatsapp::TemplateSubmitService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:api_key) { whatsapp_channel.provider_config['api_key'] }
  let(:business_account_id) { whatsapp_channel.provider_config['business_account_id'] }
  let(:expected_url) { "https://graph.facebook.com/v22.0/#{business_account_id}/message_templates" }

  let(:valid_payload) do
    {
      name: 'evento_lembrete_dia_anterior',
      language: 'pt_BR',
      category: 'UTILITY',
      components: [
        { type: 'BODY', text: 'Olá {{1}}, sua aula é amanhã. Acesse {{2}}',
          example: { body_text: [['João', 'https://example.com']] } },
        { type: 'BUTTONS', buttons: [{ type: 'URL', text: 'Entrar', url: 'https://example.com/{{1}}', example: ['abc'] }] }
      ]
    }
  end

  let(:service) { described_class.new(whatsapp_channel: whatsapp_channel, template_payload: valid_payload) }

  describe '#perform' do
    context 'with a valid payload' do
      let(:success_response) do
        # rubocop:disable RSpec/VerifiedDoubles
        double('response', success?: true, body: '{"id":"123","status":"PENDING"}')
        # rubocop:enable RSpec/VerifiedDoubles
      end

      before do
        allow(success_response).to receive(:[]).with('id').and_return('123')
        allow(success_response).to receive(:[]).with('status').and_return('PENDING')
        allow(HTTParty).to receive(:post).and_return(success_response)
      end

      it 'POSTs to the correct Meta URL with Bearer auth and the payload body' do
        service.perform

        expect(HTTParty).to have_received(:post).with(
          expected_url,
          headers: {
            'Authorization' => "Bearer #{api_key}",
            'Content-Type' => 'application/json'
          },
          body: anything,
          timeout: 15
        )
      end

      it 'sends the components verbatim including nested samples' do
        service.perform

        expect(HTTParty).to have_received(:post) do |_url, options|
          parsed_body = JSON.parse(options[:body])
          expect(parsed_body['components']).to eq(JSON.parse(valid_payload[:components].to_json))
        end
      end

      it 'returns the Meta template_id and status' do
        result = service.perform
        expect(result).to eq({ success: true, template_id: '123', status: 'PENDING' })
      end
    end

    context 'with invalid input' do
      before { allow(HTTParty).to receive(:post) }

      it 'raises when name is missing without calling Meta' do
        payload = valid_payload.merge(name: nil)
        expect { described_class.new(whatsapp_channel: whatsapp_channel, template_payload: payload).perform }
          .to raise_error(CustomExceptions::Whatsapp::InvalidTemplate, /name is required/)
        expect(HTTParty).not_to have_received(:post)
      end

      it 'raises when name has invalid characters without calling Meta' do
        payload = valid_payload.merge(name: 'Invalid Name!')
        expect { described_class.new(whatsapp_channel: whatsapp_channel, template_payload: payload).perform }
          .to raise_error(CustomExceptions::Whatsapp::InvalidTemplate, /lowercase/)
        expect(HTTParty).not_to have_received(:post)
      end

      it 'raises when category is not allowed without calling Meta' do
        payload = valid_payload.merge(category: 'AUTHENTICATION')
        expect { described_class.new(whatsapp_channel: whatsapp_channel, template_payload: payload).perform }
          .to raise_error(CustomExceptions::Whatsapp::InvalidTemplate, /category must be one of/)
        expect(HTTParty).not_to have_received(:post)
      end

      it 'raises when language is missing without calling Meta' do
        payload = valid_payload.merge(language: '')
        expect { described_class.new(whatsapp_channel: whatsapp_channel, template_payload: payload).perform }
          .to raise_error(CustomExceptions::Whatsapp::InvalidTemplate, /language is required/)
        expect(HTTParty).not_to have_received(:post)
      end

      it 'raises when components are missing without calling Meta' do
        payload = valid_payload.merge(components: nil)
        expect { described_class.new(whatsapp_channel: whatsapp_channel, template_payload: payload).perform }
          .to raise_error(CustomExceptions::Whatsapp::InvalidTemplate, /components are required/)
        expect(HTTParty).not_to have_received(:post)
      end

      it 'raises when no BODY component is present without calling Meta' do
        payload = valid_payload.merge(components: [{ type: 'FOOTER', text: 'footer only' }])
        expect { described_class.new(whatsapp_channel: whatsapp_channel, template_payload: payload).perform }
          .to raise_error(CustomExceptions::Whatsapp::InvalidTemplate, /must include a BODY/)
        expect(HTTParty).not_to have_received(:post)
      end
    end

    context 'when Meta returns an error' do
      let(:error_response) do
        # rubocop:disable RSpec/VerifiedDoubles
        double('response', success?: false, code: 400,
                           body: '{"error":{"message":"Invalid parameter","error_user_msg":"Template name already exists"}}')
        # rubocop:enable RSpec/VerifiedDoubles
      end

      before do
        allow(HTTParty).to receive(:post).and_return(error_response)
        allow(Rails.logger).to receive(:error)
      end

      it 'raises a submission error with the Meta message' do
        expect { service.perform }
          .to raise_error(CustomExceptions::Whatsapp::TemplateSubmissionError, 'Template name already exists')
      end

      it 'never leaks the api_key in the raised error message' do
        service.perform
      rescue CustomExceptions::Whatsapp::TemplateSubmissionError => e
        expect(e.message).not_to include(api_key)
      end

      it 'never logs the api_key' do
        allow(Rails.logger).to receive(:error)
        begin
          service.perform
        rescue CustomExceptions::Whatsapp::TemplateSubmissionError
          nil
        end
        expect(Rails.logger).to have_received(:error) do |msg|
          expect(msg).not_to include(api_key)
        end
      end
    end

    context 'when the Meta network call fails (transport error)' do
      before { allow(HTTParty).to receive(:post).and_raise(Net::OpenTimeout) }

      it 'validates the payload before reaching the network rescue' do
        payload = valid_payload.merge(name: nil)
        expect { described_class.new(whatsapp_channel: whatsapp_channel, template_payload: payload).perform }
          .to raise_error(CustomExceptions::Whatsapp::InvalidTemplate, /name is required/)
        expect(HTTParty).not_to have_received(:post)
      end

      it 'raises an operator-safe TemplateSubmissionError, not the raw transport error' do
        expect { service.perform }
          .to raise_error(CustomExceptions::Whatsapp::TemplateSubmissionError, 'Could not reach Meta, please retry')
      end

      it 'never leaks the api_key in the re-raised error message' do
        service.perform
      rescue CustomExceptions::Whatsapp::TemplateSubmissionError => e
        expect(e.message).not_to include(api_key)
      end
    end
  end
end
