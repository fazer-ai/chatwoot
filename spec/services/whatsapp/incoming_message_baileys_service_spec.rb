require 'rails_helper'

describe Whatsapp::IncomingMessageBaileysService do
  describe '#perform' do
    let!(:whatsapp_channel) do
      create(:channel_whatsapp, provider: 'baileys', sync_templates: false, validate_provider_config: false).tap do |channel|
        channel.provider_config['webhook_verify_token'] = 'valid_token'
        channel.save!
      end
    end
    let(:inbox) { whatsapp_channel.inbox }

    context 'when webhook verify token is invalid' do
      it 'raises an InvalidWebhookVerifyToken error' do
        params = {
          webhookVerifyToken: 'invalid_token'
        }.with_indifferent_access

        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.to raise_error(Whatsapp::IncomingMessageBaileysService::InvalidWebhookVerifyToken)
      end
    end

    context 'when event or data is blank' do
      it 'returns early and does nothing' do
        params = {
          webhookVerifyToken: 'valid_token',
          event: '',
          data: {}
        }.with_indifferent_access

        service = described_class.new(inbox: inbox, params: params)
        expect { service.perform }.not_to(change { inbox.channel.reload.provider_connection })
      end
    end

    context 'when processing a connection update event' do
      it 'updates the channel provider_connection' do
        # NOTE: Validates all expected parameters of the "provider_connection" even if there are no event that send them all together
        params = {
          webhookVerifyToken: 'valid_token',
          event: 'connection.update',
          data: { connection: 'open', qrDataUrl: 'http://example.com/qr', error: 'wrong_phone_number' }
        }.with_indifferent_access

        expect(Rails.logger).to receive(:error).with('Baileys connection error: wrong_phone_number')
        described_class.new(inbox: inbox, params: params).perform
        expect(inbox.channel.provider_connection).to include(
          'connection' => 'open',
          'qr_data_url' => 'http://example.com/qr',
          'error' => I18n.t('errors.inboxes.channel.provider_connection.wrong_phone_number')
        )
      end
    end

    context 'when processing messages upsert event with a notify text message' do
      let(:raw_message) do
        {
          key: { id: 'msg_123', remoteJid: '5511912345678@s.whatsapp.net', fromMe: false },
          message: { conversation: 'Hello from Baileys' },
          pushName: 'John Doe'
        }
      end

      let(:params) do
        {
          webhookVerifyToken: 'valid_token',
          event: 'messages.upsert',
          data: {
            type: 'notify',
            messages: [raw_message]
          }
        }.with_indifferent_access
      end

      before do
        allow_any_instance_of(described_class).to receive(:find_message_by_source_id).and_return(nil) # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(described_class).to receive(:message_under_process?).and_return(false) # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(described_class).to receive(:cache_message_source_id_in_redis).and_return(nil) # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(described_class).to receive(:clear_message_source_id_from_redis).and_return(nil) # rubocop:disable RSpec/AnyInstance
      end

      it 'creates a new incoming text message with the proper content' do
        described_class.new(inbox: inbox, params: params).perform

        conversation = inbox.conversations.last
        message = conversation.messages.last

        expect(message).to be_present
        expect(message.content).to eq('Hello from Baileys')
        expect(message.message_type).to eq('incoming')

        contact = message.sender
        expect(contact).to be_present
        expect(contact.name).to eq('John Doe')
      end
    end
  end
end
