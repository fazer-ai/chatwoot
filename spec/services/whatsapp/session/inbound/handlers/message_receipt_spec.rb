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

  context 'when the id covers every card of a shared-contact message' do
    let!(:second_card) do
      create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                       message_type: :outgoing, status: :sent, source_id: message.source_id)
    end

    it 'moves all of them forward' do
      expect(dispatch).to eq(:handled)

      expect(message.reload.status).to eq('delivered')
      expect(second_card.reload.status).to eq('delivered')
    end
  end

  # The race that motivates the locked write is covered where it happens, in the
  # StatusTransition unit; this only checks the failure reaches the row it names.
  context 'when the send failed for a message already deleted' do
    let(:type) { 'failed' }
    let(:receipt) do
      model::Events::MessageReceipt.new(chat: model::Address.phone('5541999990000'),
                                        message_ids: [message.source_id], type: 'failed',
                                        error: 'recipient unreachable')
    end

    before do
      message
      Message.find(message.id).update!(content_attributes: { 'deleted' => true })
    end

    it 'records the error without undeleting the message' do
      expect(dispatch).to eq(:handled)

      expect(message.reload).to have_attributes(status: 'failed', external_error: 'recipient unreachable')
      expect(message.content_attributes['deleted']).to be(true)
    end
  end

  context 'when the contact read it' do
    let(:type) { 'read' }

    it 'marks the message read' do
      expect(dispatch).to eq(:handled)
      expect(message.reload.status).to eq('read')
    end

    # The contact reading us says nothing about what we have seen. Treating it as a
    # read on our side would clear the unread badge for incoming messages that arrived
    # before the receipt and that nobody here has opened.
    it 'leaves the unread badge alone' do
      conversation.update_columns(agent_last_seen_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations
      incoming = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                  message_type: :incoming)

      expect { dispatch }.not_to(change { conversation.reload.agent_last_seen_at })
      expect(conversation.reload.unread_incoming_messages).to include(incoming)
    end
  end

  context 'when one of our own devices marked the chat read' do
    let(:type) { 'read' }
    let(:message) do
      create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                       message_type: :incoming, status: :sent, source_id: '3EB0AAAA0002')
    end

    it 'marks the thread seen' do
      expect(dispatch).to eq(:handled)
      expect(conversation.reload.agent_last_seen_at).to be_present
    end

    it 'still advances the timestamps when the status has nowhere left to go' do
      message.update!(status: :read)
      conversation.update_columns(agent_last_seen_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { dispatch }.to(change { conversation.reload.agent_last_seen_at })
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
