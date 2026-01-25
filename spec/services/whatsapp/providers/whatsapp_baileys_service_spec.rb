require 'rails_helper'

describe Whatsapp::Providers::WhatsappBaileysService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) { create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false) }
  let(:message) { create(:message, inbox: whatsapp_channel.inbox, source_id: 'msg_123', content_attributes: { external_created_at: 123 }) }

  let(:test_send_phone_number) { '551187654321' }
  let(:test_send_jid) { '551187654321@s.whatsapp.net' }

  before do
    stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_CLIENT_NAME', 'chatwoot-test')
  end

  describe '.status' do
    context 'when DEFAULT_URL or DEFAULT_API_KEY are missing' do
      it 'raises ProviderUnavailableError when DEFAULT_URL is blank' do
        stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_URL', '')
        stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_API_KEY', 'test_key')

        expect do
          described_class.status
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError,
                           'Missing BAILEYS_PROVIDER_DEFAULT_URL or BAILEYS_PROVIDER_DEFAULT_API_KEY setup')
      end

      it 'raises ProviderUnavailableError when DEFAULT_API_KEY is blank' do
        stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_URL', 'http://test.com')
        stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_API_KEY', '')

        expect do
          described_class.status
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError,
                           'Missing BAILEYS_PROVIDER_DEFAULT_URL or BAILEYS_PROVIDER_DEFAULT_API_KEY setup')
      end

      it 'raises ProviderUnavailableError when both are blank' do
        stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_URL', nil)
        stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_API_KEY', nil)

        expect do
          described_class.status
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError,
                           'Missing BAILEYS_PROVIDER_DEFAULT_URL or BAILEYS_PROVIDER_DEFAULT_API_KEY setup')
      end
    end

    context 'when DEFAULT_URL and DEFAULT_API_KEY are present' do
      before do
        stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_URL', 'http://test.com')
        stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_API_KEY', 'test_key')
      end

      context 'when response is successful' do
        it 'returns the status response with symbolized keys' do
          stub_request(:get, 'http://test.com/status')
            .with(headers: { 'x-api-key' => 'test_key' })
            .to_return(
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: { packageInfo: { version: '1.0.0' } }.to_json
            )

          result = described_class.status

          expect(result).to eq({ packageInfo: { version: '1.0.0' } })
        end
      end

      context 'when response is unsuccessful' do
        it 'logs the error and raises ProviderUnavailableError' do
          stub_request(:get, 'http://test.com/status')
            .with(headers: { 'x-api-key' => 'test_key' })
            .to_return(
              status: 500,
              body: 'Internal Server Error',
              headers: {}
            )

          allow(Rails.logger).to receive(:error)

          expect do
            described_class.status
          end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError, 'Baileys API is unavailable')

          expect(Rails.logger).to have_received(:error).with('Internal Server Error')
        end
      end
    end
  end

  describe '#setup_channel_provider' do
    context 'when response is successful' do
      it 'calls the connection endpoint' do
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              clientName: 'chatwoot-test',
              webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
              webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token'],
              includeMedia: false
            }.to_json
          )
          .to_return(status: 200)

        response = service.setup_channel_provider

        expect(response).to be(true)
      end
    end

    context 'when response is unsuccessful' do
      it 'raises ProviderUnavailableError and logs the error' do
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              clientName: 'chatwoot-test',
              webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
              webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token'],
              includeMedia: false
            }.to_json
          )
          .to_return(
            status: 400,
            body: 'error message',
            headers: {}
          )

        allow(Rails.logger).to receive(:error)

        expect do
          service.setup_channel_provider
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

        expect(Rails.logger).to have_received(:error).with('error message').twice
      end
    end
  end

  describe '#disconnect_channel_provider' do
    context 'when response is successful' do
      it 'disconnects the whatsapp connection' do
        stub_request(:delete, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .with(headers: stub_headers(whatsapp_channel))
          .to_return(status: 200)

        response = service.disconnect_channel_provider

        expect(response).to be(true)
      end
    end

    context 'when response is unsuccessful' do
      it 'raises ProviderUnavailableError and logs the error' do
        # Stub the failing request
        stub_request(:delete, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .with(headers: stub_headers(whatsapp_channel))
          .to_return(
            status: 400,
            body: 'error message',
            headers: {}
          )

        # Stub the reconnection attempt
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        allow(Rails.logger).to receive(:error)

        expect do
          service.disconnect_channel_provider
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

        expect(Rails.logger).to have_received(:error).with('error message')
      end
    end
  end

  describe '#send_message' do
    let(:request_path) { "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/send-message" }
    let(:result_body) { { 'data' => { 'key' => { 'id' => 'msg_123' } } } }

    context 'when message is unsupported' do
      it 'updates the message with content attribute is_unsupported' do
        unsupported_message = create(:message, content: nil)

        service.send_message(test_send_phone_number, unsupported_message)

        expect(unsupported_message.is_unsupported).to be(true)
      end
    end

    context 'when message is input_csat' do
      before do
        allow(message).to receive(:outgoing_content).and_return('Please rate us http://example.com/survey')
        message.content_type = :input_csat
      end

      it 'sends the message with survey url' do
        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { text: 'Please rate us http://example.com/survey' }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, message)

        expect(result).to eq('msg_123')
      end
    end

    context 'when message has attachment' do
      let(:base64_image) { 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' }

      before do
        message.attachments.create!(
          account_id: message.account_id,
          file_type: 'image',
          file: {
            io: StringIO.new(Base64.decode64(base64_image)),
            filename: 'image.png'
          }
        )
      end

      it 'sends the attachment message' do
        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { fileName: 'image.png', caption: message.content, image: base64_image }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, message)

        expect(result).to eq('msg_123')
      end

      it 'omits caption if message content is empty' do
        message.update!(content: nil)
        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { fileName: 'image.png', image: base64_image }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, message)

        expect(result).to eq('msg_123')
      end
    end

    context 'when message is an audio file' do
      let(:base64_audio) { 'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=' }

      before do
        message.attachments.create!(
          account_id: message.account_id,
          file_type: 'audio',
          file: {
            io: StringIO.new(Base64.decode64(base64_audio)),
            filename: 'audio.wav'
          }
        )
      end

      it 'sends the audio message' do
        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { fileName: 'audio.wav', caption: message.content, audio: base64_audio }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, message)

        expect(result).to eq('msg_123')
      end

      it 'sends message with ptt true if message is recorded audio' do
        message.attachments.first.update!(meta: { is_recorded_audio: true })

        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { fileName: 'audio.wav', caption: message.content, audio: base64_audio, ptt: true }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, message)

        expect(result).to eq('msg_123')
      end
    end

    context 'when message is a text' do
      it 'sends the message' do
        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { text: message.content }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, message)

        expect(result).to eq('msg_123')
      end

      it 'updates the message external_created_at' do
        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { text: message.content }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: { 'data' => { 'key' => { 'id' => 'msg_123' }, 'messageTimestamp' => 1_748_003_165 } }.to_json
          )

        service.send_message(test_send_phone_number, message)

        expect(message.reload.content_attributes['external_created_at']).to eq(1_748_003_165)
      end
    end

    context 'when message is a reaction' do
      let(:inbox) { whatsapp_channel.inbox }
      let(:account_user) { create(:account_user, account: inbox.account) }
      let(:contact) { create(:contact, account: inbox.account, name: 'John Doe', phone_number: "+#{test_send_phone_number}") }
      let(:conversation) do
        contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: test_send_phone_number)
        create(:conversation, inbox: inbox, contact_inbox: contact_inbox)
      end

      it 'sends the reaction message for outgoing message' do
        message = create(:message, inbox: inbox, conversation: conversation, sender: account_user, message_type: 'outgoing', source_id: 'msg_123')
        reaction = create(:message, inbox: inbox, conversation: conversation, sender: account_user, content: '👍',
                                    content_attributes: { is_reaction: true, in_reply_to: message.id })
        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { react: { key: { id: message.source_id,
                                                remoteJid: test_send_jid,
                                                fromMe: true },
                                         text: '👍' } }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: { 'data' => { 'key' => { 'id' => 'reaction_123' } } }.to_json
          )

        result = service.send_message(test_send_phone_number, reaction)

        expect(result).to eq('reaction_123')
      end

      it 'sends the reaction message for incoming message' do
        message = create(:message, inbox: inbox, conversation: conversation, sender: contact, source_id: 'msg_123')
        reaction = create(:message, inbox: inbox, conversation: conversation, sender: account_user, content: '👍',
                                    content_attributes: { is_reaction: true, in_reply_to: message.id })
        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { react: { key: { id: message.source_id,
                                                remoteJid: test_send_jid,
                                                fromMe: false },
                                         text: '👍' } }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: { 'data' => { 'key' => { 'id' => 'reaction_123' } } }.to_json
          )

        result = service.send_message(test_send_phone_number, reaction)

        expect(result).to eq('reaction_123')
      end
    end

    context 'when message is a reply to another message' do
      let(:inbox) { whatsapp_channel.inbox }
      let(:account_user) { create(:account_user, account: inbox.account) }
      let(:contact) { create(:contact, account: inbox.account, name: 'John Doe', phone_number: "+#{test_send_phone_number}") }
      let(:conversation) do
        contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: test_send_phone_number)
        create(:conversation, inbox: inbox, contact_inbox: contact_inbox)
      end

      it 'sends text reply to outgoing message with quotedMessage' do
        original_message = create(:message, inbox: inbox, conversation: conversation, sender: account_user,
                                            message_type: 'outgoing', source_id: 'original_msg_123', content: 'Original text')
        reply_message = create(:message, inbox: inbox, conversation: conversation, sender: account_user,
                                         content: 'Reply text', content_attributes: { in_reply_to_external_id: original_message.source_id })

        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: {
                text: 'Reply text',
                quotedMessage: {
                  key: {
                    id: 'original_msg_123',
                    remoteJid: test_send_jid,
                    fromMe: true
                  },
                  message: { conversation: 'Original text' }
                }
              }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, reply_message)

        expect(result).to eq('msg_123')
      end

      it 'sends text reply to incoming message with quotedMessage' do
        original_message = create(:message, inbox: inbox, conversation: conversation, sender: contact,
                                            message_type: 'incoming', source_id: 'incoming_msg_456', content: 'Incoming text')
        reply_message = create(:message, inbox: inbox, conversation: conversation, sender: account_user,
                                         content: 'Reply to incoming', content_attributes: { in_reply_to_external_id: original_message.source_id })

        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: {
                text: 'Reply to incoming',
                quotedMessage: {
                  key: {
                    id: 'incoming_msg_456',
                    remoteJid: test_send_jid,
                    fromMe: false
                  },
                  message: { conversation: 'Incoming text' }
                }
              }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, reply_message)

        expect(result).to eq('msg_123')
      end

      it 'sends reply to message with image attachment' do
        original_message = create(:message, inbox: inbox, conversation: conversation, sender: contact,
                                            message_type: 'incoming', source_id: 'image_msg_789', content: 'Check this image')
        original_message.attachments.create!(account_id: original_message.account_id, file_type: 'image',
                                             file: { io: StringIO.new('fake'), filename: 'image.png' })

        reply_message = create(:message, inbox: inbox, conversation: conversation, sender: account_user,
                                         content: 'Nice image!', content_attributes: { in_reply_to_external_id: original_message.source_id })

        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: {
                text: 'Nice image!',
                quotedMessage: {
                  key: {
                    id: 'image_msg_789',
                    remoteJid: test_send_jid,
                    fromMe: false
                  },
                  message: { imageMessage: { caption: 'Check this image' } }
                }
              }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, reply_message)

        expect(result).to eq('msg_123')
      end

      it 'sends message without quotedMessage when in_reply_to_external_id is blank' do
        regular_message = create(:message, inbox: inbox, conversation: conversation, sender: account_user, content: 'Regular message')

        stub_request(:post, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              messageContent: { text: 'Regular message' }
            }.to_json
          )
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        result = service.send_message(test_send_phone_number, regular_message)

        expect(result).to eq('msg_123')
      end
    end

    context 'when request is unsuccessful' do
      it 'raises ProviderUnavailableError' do
        stub_request(:post, request_path)
          .to_return(
            status: 400,
            headers: { 'Content-Type' => 'application/json' },
            body: result_body.to_json
          )

        # Stub the reconnection attempt
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        expect do
          service.send_message(test_send_phone_number, message)
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)
      end
    end
  end

  describe '#media_url' do
    it 'returns the media url' do
      media_id = '12345'
      expected_url = "#{whatsapp_channel.provider_config['provider_url']}/media/#{media_id}"

      expect(service.media_url(media_id)).to eq(expected_url)
    end
  end

  describe '#api_headers' do
    it 'returns the headers' do
      expect(service.api_headers).to eq('x-api-key' => 'test_key', 'Content-Type' => 'application/json')
    end
  end

  describe '#validate_provider_config?' do
    context 'when response is successful' do
      it 'returns true' do
        stub_request(:get, "#{whatsapp_channel.provider_config['provider_url']}/status/auth")
          .with(headers: stub_headers(whatsapp_channel))
          .to_return(status: 200, body: '', headers: {})

        expect(service.validate_provider_config?).to be(true)
      end
    end

    context 'when response is unsuccessful' do
      it 'logs the error and returns false' do
        stub_request(:get, "#{whatsapp_channel.provider_config['provider_url']}/status/auth")
          .with(headers: stub_headers(whatsapp_channel))
          .to_return(status: 400, body: 'error message', headers: {})
        allow(Rails.logger).to receive(:error).with('error message')

        expect(service.validate_provider_config?).to be(false)
        expect(Rails.logger).to have_received(:error)
      end
    end
  end

  describe '#read_messages' do
    it 'send read messages request' do
      stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/read-messages")
        .with(
          headers: stub_headers(whatsapp_channel),
          body: { keys: [{ id: message.source_id, remoteJid: test_send_jid, fromMe: false }] }.to_json
        ).to_return(status: 200, body: '', headers: {})

      result = service.read_messages([message], recipient_id: test_send_phone_number)

      expect(result).to be(true)
    end

    context 'when request is unsuccessful' do
      it 'raises ProviderUnavailableError' do
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/read-messages")
          .with(
            headers: stub_headers(whatsapp_channel),
            body: { keys: [{ id: message.source_id, remoteJid: test_send_jid, fromMe: false }] }.to_json
          ).to_return(status: 400, body: 'error message', headers: {})

        # Stub the reconnection attempt
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        expect do
          service.read_messages([message], recipient_id: test_send_phone_number)
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)
      end
    end
  end

  describe '#unread_message' do
    it 'send unread message request' do
      stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/chat-modify")
        .with(
          headers: stub_headers(whatsapp_channel),
          body: {
            jid: test_send_jid,
            mod: {
              markRead: false,
              lastMessages: [
                {
                  key: { id: 'msg_123', remoteJid: test_send_jid, fromMe: false },
                  messageTimestamp: 123
                }
              ]
            }
          }.to_json
        ).to_return(status: 200)

      result = service.unread_message(test_send_phone_number, message)

      expect(result).to be(true)
    end

    context 'when request is unsuccessful' do
      it 'raises ProviderUnavailableError' do
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/chat-modify")
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              mod: {
                markRead: false,
                lastMessages: [
                  {
                    key: { id: 'msg_123', remoteJid: test_send_jid, fromMe: false },
                    messageTimestamp: 123
                  }
                ]
              }
            }.to_json
          ).to_return(status: 400, body: 'error message', headers: {})

        # Stub the reconnection attempt
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        expect do
          service.unread_message(test_send_phone_number, message)
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)
      end
    end
  end

  describe '#received_messages' do
    it 'send received messages request' do
      stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/send-receipts")
        .with(
          headers: stub_headers(whatsapp_channel),
          body: {
            keys: [{ id: message.source_id, remoteJid: test_send_jid, fromMe: false }]
          }.to_json
        ).to_return(status: 200)

      result = service.received_messages(test_send_phone_number, [message])

      expect(result).to be(true)
    end

    context 'when request is unsuccessful' do
      it 'raises ProviderUnavailableError' do
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/send-receipts")
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              keys: [{ id: message.source_id, remoteJid: test_send_jid, fromMe: false }]
            }.to_json
          ).to_return(status: 400, body: 'error message', headers: {})

        # Stub the reconnection attempt
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        expect do
          service.received_messages(test_send_phone_number, [message])
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)
      end
    end
  end

  describe '#toggle_typing_status' do
    let(:request_path) { "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/presence" }

    it 'calls presence endpoint for typing on' do
      request = stub_request(:patch, request_path)
                .with(
                  headers: stub_headers(whatsapp_channel),
                  body: {
                    toJid: test_send_jid,
                    type: 'composing'
                  }.to_json
                )
                .to_return(status: 200)

      service.toggle_typing_status(Events::Types::CONVERSATION_TYPING_ON, recipient_id: test_send_phone_number)

      expect(request).to have_been_requested
    end

    it 'calls presence endpoint for recording' do
      request = stub_request(:patch, request_path)
                .with(
                  headers: stub_headers(whatsapp_channel),
                  body: {
                    toJid: test_send_jid,
                    type: 'recording'
                  }.to_json
                )
                .to_return(status: 200)

      service.toggle_typing_status(Events::Types::CONVERSATION_RECORDING, recipient_id: test_send_phone_number)

      expect(request).to have_been_requested
    end

    it 'calls presence endpoint for typing off' do
      request = stub_request(:patch, request_path)
                .with(
                  headers: stub_headers(whatsapp_channel),
                  body: {
                    toJid: test_send_jid,
                    type: 'paused'
                  }.to_json
                )
                .to_return(status: 200)

      service.toggle_typing_status(Events::Types::CONVERSATION_TYPING_OFF, recipient_id: test_send_phone_number)

      expect(request).to have_been_requested
    end

    context 'when request is unsuccessful' do
      it 'raises ProviderUnavailableError and logs the error' do
        stub_request(:patch, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              toJid: test_send_jid,
              type: 'composing'
            }.to_json
          )
          .to_return(
            status: 400,
            body: 'error message',
            headers: {}
          )

        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        allow(Rails.logger).to receive(:error)

        expect do
          service.toggle_typing_status(Events::Types::CONVERSATION_TYPING_ON, recipient_id: test_send_phone_number)
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

        expect(Rails.logger).to have_received(:error).with('error message')
      end
    end
  end

  describe '#update_presence' do
    let(:request_path) { "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/presence" }

    it 'calls presence endpoint' do
      request = stub_request(:patch, request_path)
                .with(
                  headers: stub_headers(whatsapp_channel),
                  body: {
                    type: 'available'
                  }.to_json
                )
                .to_return(status: 200)

      service.update_presence('online')

      expect(request).to have_been_requested
    end

    context 'when request is unsuccessful' do
      it 'raises ProviderUnavailableError and logs the error' do
        stub_request(:patch, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              type: 'available'
            }.to_json
          )
          .to_return(
            status: 400,
            body: 'error message',
            headers: {}
          )

        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        allow(Rails.logger).to receive(:error)

        expect do
          service.update_presence('online')
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

        expect(Rails.logger).to have_received(:error).with('error message')
      end
    end
  end

  describe '#on_whatsapp' do
    let(:request_path) { "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/on-whatsapp" }
    let(:phone_number) { '+123456789' }

    context 'when response is successful' do
      it 'requests whatsapp check' do
        stub_request(:post, request_path)
          .with(headers: stub_headers(whatsapp_channel), body: { jids: ["#{phone_number.delete('+')}@s.whatsapp.net"] }.to_json)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: [{ jid: "#{phone_number.delete('+')}@s.whatsapp.net", exists: true }].to_json
          )

        response = service.on_whatsapp(phone_number)

        expect(response).to eq({ 'jid' => "#{phone_number.delete('+')}@s.whatsapp.net", 'exists' => true })
      end

      it 'returns default check response' do
        stub_request(:post, request_path)
          .with(headers: stub_headers(whatsapp_channel), body: { jids: ["#{phone_number.delete('+')}@s.whatsapp.net"] }.to_json)
          .to_return(
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: [].to_json
          )

        response = service.on_whatsapp(phone_number)

        expect(response).to eq({ 'jid' => "#{phone_number.delete('+')}@s.whatsapp.net", 'exists' => false })
      end
    end

    context 'when response is unsuccessful' do
      it 'raises ProviderUnavailableError and logs the error' do
        stub_request(:post, request_path)
          .with(headers: stub_headers(whatsapp_channel), body: { jids: ["#{phone_number.delete('+')}@s.whatsapp.net"] }.to_json)
          .to_return(
            status: 400,
            body: 'error message',
            headers: {}
          )

        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        allow(Rails.logger).to receive(:error)

        expect do
          service.on_whatsapp(phone_number)
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

        expect(Rails.logger).to have_received(:error).with('error message')
      end
    end
  end

  describe '#delete_message' do
    let(:request_path) { "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/messages" }
    let(:outgoing_message) { create(:message, inbox: whatsapp_channel.inbox, source_id: 'msg_456', message_type: :outgoing) }
    let(:incoming_message) { create(:message, inbox: whatsapp_channel.inbox, source_id: 'msg_789', message_type: :incoming) }

    context 'when deleting an outgoing message' do
      it 'sends delete request with fromMe true' do
        stub_request(:delete, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              key: {
                id: outgoing_message.source_id,
                remoteJid: test_send_jid,
                fromMe: true
              }
            }.to_json
          )
          .to_return(status: 200, body: '{}')

        result = service.delete_message(test_send_phone_number, outgoing_message)

        expect(result).to be(true)
      end
    end

    context 'when deleting an incoming message' do
      it 'sends delete request with fromMe false' do
        stub_request(:delete, request_path)
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              jid: test_send_jid,
              key: {
                id: incoming_message.source_id,
                remoteJid: test_send_jid,
                fromMe: false
              }
            }.to_json
          )
          .to_return(status: 200, body: '{}')

        result = service.delete_message(test_send_phone_number, incoming_message)

        expect(result).to be(true)
      end
    end

    context 'when response is unsuccessful' do
      it 'raises ProviderUnavailableError and logs the error' do
        stub_request(:delete, request_path)
          .with(headers: stub_headers(whatsapp_channel))
          .to_return(status: 400, body: 'error message')

        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .to_return(status: 200)

        allow(Rails.logger).to receive(:error)

        expect do
          service.delete_message(test_send_phone_number, outgoing_message)
        end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

        expect(Rails.logger).to have_received(:error).with('error message')
      end
    end
  end

  context 'when environment variable BAILEYS_PROVIDER_DEFAULT_URL is set' do
    it 'uses the base url from the environment variable' do
      stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_URL', 'http://test.com')
      whatsapp_channel.update!(provider_config: {})

      expect(service.send(:provider_url)).to eq('http://test.com')
    end
  end

  context 'when environment variable BAILEYS_PROVIDER_DEFAULT_API_KEY is set' do
    it 'uses the API key from the environment variable' do
      stub_const('Whatsapp::Providers::WhatsappBaileysService::DEFAULT_API_KEY', 'key')
      whatsapp_channel.update!(provider_config: {})

      expect(service.send(:api_key)).to eq('key')
    end
  end

  describe 'error handling' do
    describe '#handle_channel_error' do
      it 'updates provider connection to close' do
        whatsapp_channel.update!(provider_connection: { 'connection' => 'open' })

        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              clientName: 'chatwoot-test',
              webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
              webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token'],
              includeMedia: false
            }.to_json
          )
          .to_return(status: 200)

        service.send(:handle_channel_error)

        expect(whatsapp_channel.reload.provider_connection['connection']).to eq('close')
      end

      it 'attempts to reconnect by calling setup_channel_provider' do
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              clientName: 'chatwoot-test',
              webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
              webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token'],
              includeMedia: false
            }.to_json
          )
          .to_return(status: 200)

        service.send(:handle_channel_error)

        expect(WebMock).to have_requested(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
      end

      it 'logs error and does not raise when reconnection fails' do
        stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
          .with(
            headers: stub_headers(whatsapp_channel),
            body: {
              clientName: 'chatwoot-test',
              webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
              webhookVerifyToken: whatsapp_channel.provider_config['webhook_verify_token'],
              includeMedia: false
            }.to_json
          )
          .to_return(status: 400, body: 'reconnection failed')

        allow(Rails.logger).to receive(:error)

        expect { service.send(:handle_channel_error) }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(/Failed to reconnect channel after error/)
      end

      it 'prevents infinite loop with @handling_error flag' do
        service.instance_variable_set(:@handling_error, true)

        expect(HTTParty).not_to receive(:post)

        service.send(:handle_channel_error)

        expect(whatsapp_channel.reload.provider_connection['connection']).to eq('close')
      end
    end

    describe 'error handling wrapper' do
      context 'when send_message fails' do
        it 'calls handle_channel_error and re-raises the error' do
          stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/send-message")
            .to_return(status: 500, body: 'server error')

          stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
            .to_return(status: 200)

          whatsapp_channel.update!(provider_connection: { 'connection' => 'open' })

          expect do
            service.send_message(test_send_phone_number, message)
          end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

          expect(whatsapp_channel.reload.provider_connection['connection']).to eq('close')

          expect(WebMock).to have_requested(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
        end
      end

      context 'when setup_channel_provider fails' do
        it 'calls handle_channel_error and re-raises the error' do
          stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
            .to_return(status: 500, body: 'server error')

          whatsapp_channel.update!(provider_connection: { 'connection' => 'open' })
          allow(Rails.logger).to receive(:error)

          expect do
            service.setup_channel_provider
          end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

          expect(whatsapp_channel.reload.provider_connection['connection']).to eq('close')

          expect(Rails.logger).to have_received(:error).with(/Failed to reconnect channel after error/)
        end
      end

      context 'when toggle_typing_status fails' do
        it 'calls handle_channel_error and re-raises the error' do
          stub_request(:patch, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/presence")
            .to_return(status: 500, body: 'server error')

          stub_request(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
            .to_return(status: 200)

          whatsapp_channel.update!(provider_connection: { 'connection' => 'open' })

          expect do
            service.toggle_typing_status(Events::Types::CONVERSATION_TYPING_ON, recipient_id: test_send_phone_number)
          end.to raise_error(Whatsapp::Providers::WhatsappBaileysService::ProviderUnavailableError)

          expect(whatsapp_channel.reload.provider_connection['connection']).to eq('close')

          expect(WebMock).to have_requested(:post, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}")
        end
      end
    end
  end

  describe '#get_profile_pic' do
    let(:test_jid) { '551187654321@s.whatsapp.net' }

    context 'when response is successful' do
      it 'returns the profile picture URL data' do
        stub_request(:get, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/profile-picture-url")
          .with(
            headers: stub_headers(whatsapp_channel),
            query: { jid: test_jid }
          )
          .to_return(
            status: 200,
            body: { data: { profilePictureUrl: 'https://pps.whatsapp.net/v/t61.24694-24/avatar.jpg', jid: test_jid } }.to_json
          )

        result = service.get_profile_pic(test_jid)

        expect(result).to eq({
                               'data' => {
                                 'profilePictureUrl' => 'https://pps.whatsapp.net/v/t61.24694-24/avatar.jpg',
                                 'jid' => test_jid
                               }
                             })
      end
    end

    context 'when response fails' do
      it 'returns nil when profile picture not found (404)' do
        stub_request(:get, "#{whatsapp_channel.provider_config['provider_url']}/connections/#{whatsapp_channel.phone_number}/profile-picture-url")
          .with(
            headers: stub_headers(whatsapp_channel),
            query: { jid: test_jid }
          )
          .to_return(
            status: 404,
            body: { error: 'Profile picture not found' }.to_json
          )

        result = service.get_profile_pic(test_jid)

        expect(result).to be_nil
      end
    end
  end

  def stub_headers(channel)
    {
      'Content-Type' => 'application/json',
      'x-api-key' => channel.provider_config['api_key']
    }
  end
end
