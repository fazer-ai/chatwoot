require 'rails_helper'

describe InternalChat::TypingStatusManager do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

  describe '#perform' do
    it 'dispatches INTERNAL_CHAT_TYPING_ON for on status' do
      params = { typing_status: 'on' }
      dispatcher = Rails.configuration.dispatcher
      allow(dispatcher).to receive(:dispatch)
      expect(dispatcher).to receive(:dispatch)
        .with('internal_chat.typing_on', anything, hash_including(channel: channel, user: user))

      described_class.new(channel: channel, user: user, params: params).perform
    end

    it 'dispatches INTERNAL_CHAT_TYPING_OFF for off status' do
      params = { typing_status: 'off' }
      dispatcher = Rails.configuration.dispatcher
      allow(dispatcher).to receive(:dispatch)
      expect(dispatcher).to receive(:dispatch)
        .with('internal_chat.typing_off', anything, hash_including(channel: channel, user: user))

      described_class.new(channel: channel, user: user, params: params).perform
    end

    it 'does not dispatch any event for unknown status' do
      params = { typing_status: 'unknown' }
      dispatcher = Rails.configuration.dispatcher
      allow(dispatcher).to receive(:dispatch)
      expect(dispatcher).not_to receive(:dispatch)
        .with('internal_chat.typing_on', anything, anything)
      expect(dispatcher).not_to receive(:dispatch)
        .with('internal_chat.typing_off', anything, anything)

      described_class.new(channel: channel, user: user, params: params).perform
    end
  end
end
