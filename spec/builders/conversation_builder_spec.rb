require 'rails_helper'

describe ConversationBuilder do
  let(:account) { create(:account) }
  let!(:sms_channel) { create(:channel_sms, account: account) }
  let!(:api_channel) { create(:channel_api, account: account) }
  let!(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let!(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_sms_inbox) { create(:contact_inbox, contact: contact, inbox: sms_inbox) }
  let(:contact_api_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox) }

  describe '#perform' do
    it 'creates sms conversation' do
      conversation = described_class.new(
        contact_inbox: contact_sms_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
    end

    it 'creates api conversation' do
      conversation = described_class.new(
        contact_inbox: contact_api_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
    end

    context 'when lock_to_single_conversation is true for sms inbox' do
      before do
        sms_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates sms conversation when existing conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
      end

      it 'returns last from existing sms conversations when existing conversation is not present' do
        create(:conversation, contact_inbox: contact_sms_inbox, contact: contact, inbox: sms_inbox)
        existing_conversation = create(:conversation, contact_inbox: contact_sms_inbox, contact: contact, inbox: sms_inbox)
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    context 'when lock_to_single_conversation is true for api inbox' do
      before do
        api_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates conversation when existing api conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
      end

      it 'returns last from existing api conversations when existing conversation is not present' do
        create(:conversation, contact_inbox: contact_api_inbox, contact: contact, inbox: api_inbox)
        existing_conversation = create(:conversation, contact_inbox: contact_api_inbox, contact: contact, inbox: api_inbox)
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    context 'when lock_to_single_conversation is true for whatsapp inbox with multiple contact_inboxes' do
      let!(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
      let!(:whatsapp_inbox) { whatsapp_channel.inbox }
      let(:contact_with_phone) { create(:contact, account: account, phone_number: '+5511912345678') }

      before { whatsapp_inbox.update!(lock_to_single_conversation: true) }

      it 'finds conversation from different contact_inbox with same contact' do
        lid_contact_inbox = create(:contact_inbox, contact: contact_with_phone, inbox: whatsapp_inbox, source_id: '12345678')
        existing_conversation = create(:conversation, contact_inbox: lid_contact_inbox, inbox: whatsapp_inbox, contact: contact_with_phone)
        phone_contact_inbox = create(:contact_inbox, contact: contact_with_phone, inbox: whatsapp_inbox, source_id: '5511912345678')

        conversation = described_class.new(contact_inbox: phone_contact_inbox, params: {}).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    # An inbox with an active bot starts its conversations pending, which is what gives the bot the
    # first turn. The caller that says otherwise is the one creating a conversation on purpose: an
    # agent reaching out proactively through the API, where a pending conversation is invisible under
    # the dashboard's default filter and the person it was created for cannot find it.
    context 'when the inbox has an active bot' do
      let(:agent_bot) { create(:agent_bot, account: account) }

      before { create(:agent_bot_inbox, inbox: api_inbox, agent_bot: agent_bot) }

      it 'honours the status the caller asked for' do
        conversation = described_class.new(contact_inbox: contact_api_inbox, params: { status: 'open' }).perform

        expect(conversation.status).to eq('open')
      end

      it 'still hands the conversation to the bot when a status was asked for' do
        conversation = described_class.new(contact_inbox: contact_api_inbox, params: { status: 'open' }).perform

        expect(conversation.assignee_agent_bot).to eq(agent_bot)
      end

      it 'starts pending when no status was asked for' do
        conversation = described_class.new(contact_inbox: contact_api_inbox, params: {}).perform

        expect(conversation.status).to eq('pending')
        expect(conversation.assignee_agent_bot).to eq(agent_bot)
      end

      # The parameter only started being read here, and a value the enum cannot take used to reach
      # the assignment and raise ArgumentError, which the API answers as a 500.
      it 'refuses a status the enum does not have' do
        builder = described_class.new(contact_inbox: contact_api_inbox, params: { status: 'bogus' })

        expect { builder.perform }.to raise_error(CustomExceptions::Conversation::InvalidStatus)
        expect(api_inbox.conversations.count).to eq(0)
      end
    end
  end
end
