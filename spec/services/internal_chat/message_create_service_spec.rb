require 'rails_helper'

describe InternalChat::MessageCreateService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

  describe '#perform' do
    it 'creates a message with content' do
      params = { content: 'Hello, world!' }

      expect do
        described_class.new(channel: channel, sender: user, params: params).perform
      end.to change(InternalChat::Message, :count).by(1)

      message = InternalChat::Message.last
      expect(message.content).to eq('Hello, world!')
      expect(message.sender).to eq(user)
      expect(message.channel).to eq(channel)
      expect(message.account).to eq(account)
    end

    it 'dispatches INTERNAL_CHAT_MESSAGE_CREATED event' do
      params = { content: 'Test message' }
      dispatcher = Rails.configuration.dispatcher
      allow(dispatcher).to receive(:dispatch)
      expect(dispatcher).to receive(:dispatch)
        .with('internal_chat.message.created', anything, hash_including(message: an_instance_of(InternalChat::Message)))

      described_class.new(channel: channel, sender: user, params: params).perform
    end

    it 'returns the created message' do
      params = { content: 'Return value test' }

      result = described_class.new(channel: channel, sender: user, params: params).perform
      expect(result).to be_a(InternalChat::Message)
      expect(result).to be_persisted
      expect(result.content).to eq('Return value test')
    end

    context 'when parent_id is provided' do
      let(:parent_message) { create(:internal_chat_message, account: account, channel: channel, sender: user) }

      it 'creates a threaded reply' do
        params = { content: 'Thread reply', parent_id: parent_message.id }

        message = described_class.new(channel: channel, sender: user, params: params).perform
        expect(message.parent_id).to eq(parent_message.id)
        expect(message.parent).to eq(parent_message)
      end
    end

    context 'when echo_id is provided' do
      it 'stores the echo_id on the message' do
        params = { content: 'Echo test', echo_id: 'client-uuid-123' }

        message = described_class.new(channel: channel, sender: user, params: params).perform
        expect(message.echo_id).to eq('client-uuid-123')
      end
    end

    context 'when content_type is specified' do
      it 'uses the provided content_type' do
        params = { content: 'System message', content_type: :system }

        message = described_class.new(channel: channel, sender: user, params: params).perform
        expect(message.content_type).to eq('system')
      end
    end
  end
end
