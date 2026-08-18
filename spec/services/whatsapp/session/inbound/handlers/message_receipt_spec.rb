require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::MessageReceipt do
  subject(:dispatch) { Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event) }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:conversation) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     message_type: :outgoing, status: :sent, source_id: '3EB0AAAA0001')
  end
  let(:receipt) do
    model::Events::MessageReceipt.new(chat: model::Address.phone('5541999990000'),
                                      message_ids: [message.source_id], type: type)
  end
  let(:type) { 'delivered' }
  let(:event) { model::Event.build(receipt) }

  it 'moves the message forward' do
    expect(dispatch).to eq(:handled)
    expect(message.reload.status).to eq('delivered')
  end

  context 'when the contact read it' do
    let(:type) { 'read' }

    it 'marks the message read and the thread seen' do
      expect(dispatch).to eq(:handled)
      expect(message.reload.status).to eq('read')
      expect(conversation.reload.agent_last_seen_at).to be_present
    end
  end

  context 'when a weaker receipt arrives late' do
    let(:type) { 'delivered' }

    before { message.update!(status: :read) }

    it 'keeps the stronger status' do
      expect(dispatch).to eq(:ignored)
      expect(message.reload.status).to eq('read')
    end
  end

  context 'when the message is not stored' do
    let(:receipt) do
      model::Events::MessageReceipt.new(chat: model::Address.phone('5541999990000'),
                                        message_ids: ['3EB0UNKNOWN'], type: 'delivered')
    end

    it 'ignores the receipt' do
      expect(dispatch).to eq(:ignored)
    end
  end

  context 'when the provider reports a failure' do
    let(:type) { 'failed' }
    let(:receipt) do
      model::Events::MessageReceipt.new(
        chat: model::Address.phone('5541999990000'), message_ids: [message.source_id], type: 'failed',
        error: model::WireError.new(code: 'recipient_not_on_whatsapp', message: 'not on whatsapp')
      )
    end

    it 'fails the message and keeps the provider reason' do
      expect(dispatch).to eq(:handled)
      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to include('not on whatsapp')
    end
  end
end
