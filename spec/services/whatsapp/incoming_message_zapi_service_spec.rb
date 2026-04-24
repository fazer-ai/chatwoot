require 'rails_helper'

describe Whatsapp::IncomingMessageZapiService do
  describe '#perform' do
    let!(:whatsapp_channel) do
      create(:channel_whatsapp, provider: 'zapi', validate_provider_config: false, received_messages: false)
    end
    let(:inbox) { whatsapp_channel.inbox }

    context 'when type is blank' do
      it 'does nothing' do
        params = { type: '' }

        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.not_to change(Message, :count)
      end

      it 'does nothing when type is nil' do
        params = {}

        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.not_to change(Message, :count)
      end
    end

    context 'when event type is unsupported' do
      it 'logs a warning message' do
        params = { type: 'unsupported_event' }
        allow(Rails.logger).to receive(:warn)

        described_class.new(inbox: inbox, params: params).perform

        expect(Rails.logger).to have_received(:warn).with(/Z-API unsupported event/)
      end
    end

    it 'dispatches the provider.event_received event' do
      params = { type: 'some_event' }
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      described_class.new(inbox: inbox, params: params).perform

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::PROVIDER_EVENT_RECEIVED,
        kind_of(Time),
        inbox: inbox,
        event: params[:type],
        payload: params
      )
    end

    context 'when a reaction removal webhook arrives' do
      let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511912345678', identifier: '12345678') }
      let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '12345678') }
      let(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox, contact: contact) }
      # Must exist so `ensure_in_reply_to` on the reaction Message we build below
      # can resolve the source_id — otherwise the before_save hook blanks
      # `in_reply_to_external_id` and the removal lookup can't find the reaction.
      let!(:target) { create(:message, conversation: conversation, source_id: 'target_msg_id', content: 'Hi') } # rubocop:disable RSpec/LetSetup
      let(:removal_params) do
        {
          type: 'ReceivedCallback',
          phone: '5511912345678',
          chatLid: '12345678',
          fromMe: false,
          messageId: 'reaction_removal_id',
          momment: (Time.current.to_i * 1000),
          senderName: 'John Doe',
          reaction: {
            value: '',
            referencedMessage: { messageId: 'target_msg_id' }
          }
        }
      end

      it 'marks an existing reaction as removed instead of creating a new message' do
        existing_reaction = create(:message,
                                   conversation: conversation,
                                   sender: contact,
                                   message_type: :incoming,
                                   content: '❤️',
                                   content_attributes: { is_reaction: true, in_reply_to_external_id: 'target_msg_id' })

        expect do
          described_class.new(inbox: inbox, params: removal_params).perform
        end.not_to(change { conversation.messages.count })

        existing_reaction.reload
        expect(existing_reaction.content).to eq('')
        expect(existing_reaction.content_attributes['deleted']).to be true
      end

      it 'dispatches conversation.updated after marking the reaction as removed' do
        create(:message,
               conversation: conversation,
               sender: contact,
               message_type: :incoming,
               content: '❤️',
               content_attributes: { is_reaction: true, in_reply_to_external_id: 'target_msg_id' })
        dispatched = []
        allow_any_instance_of(Conversation).to receive(:dispatch_conversation_updated_event) do |conv| # rubocop:disable RSpec/AnyInstance
          dispatched << conv.id
        end

        described_class.new(inbox: inbox, params: removal_params).perform

        expect(dispatched).to include(conversation.id)
      end

      it 'skips reaction removal for outgoing echoes (fromMe: true) to avoid clobbering the local update' do
        # Mirror the post-controller state: the reactions controller already
        # toggled the senderless outgoing row to deleted, so the echoed fromMe
        # webhook should hit the active-only filter and no-op.
        existing_reaction = create(:message,
                                   conversation: conversation,
                                   sender: nil,
                                   message_type: :outgoing,
                                   content: '',
                                   content_attributes: { is_reaction: true, in_reply_to_external_id: 'target_msg_id', deleted: true })
        described_class.new(inbox: inbox, params: removal_params.merge(fromMe: true, messageId: 'outgoing_echo_removal')).perform

        existing_reaction.reload
        expect(existing_reaction.content).to eq('')
        expect(existing_reaction.content_attributes['deleted']).to be(true)
      end
    end
  end
end
