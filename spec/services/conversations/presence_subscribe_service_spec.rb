require 'rails_helper'

describe Conversations::PresenceSubscribeService do
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'baileys',
           provider_config: { webhook_verify_token: 'token', presence_subscribe: presence_enabled },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5521999999999', identifier: '12345@lid') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '12345') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  before do
    stub_request(:post, "https://baileys.api/connections/#{whatsapp_channel.phone_number}")
      .to_return(status: 200, body: {}.to_json)
  end

  describe '#perform' do
    context 'when presence_subscribe is enabled' do
      let(:presence_enabled) { true }

      let(:presence_subscribe_url) { "https://baileys.api/connections/#{whatsapp_channel.phone_number}/presence-subscribe" }
      let(:json_headers) { { 'Content-Type' => 'application/json' } }

      it 'calls presence_subscribe on the channel with the contact JID' do
        stub_request(:post, presence_subscribe_url)
          .to_return(status: 200, body: { data: { subscribed: ['12345@lid'], skipped: [] } }.to_json, headers: json_headers)

        described_class.new(account, [conversation.display_id]).perform

        expect(WebMock).to have_requested(:post, presence_subscribe_url)
          .with(body: { jids: ['12345@lid'] }.to_json)
      end

      it 'falls back to phone JID when identifier is blank' do
        contact.update!(identifier: nil)
        stub_request(:post, presence_subscribe_url)
          .to_return(status: 200, body: { data: { subscribed: [], skipped: [] } }.to_json, headers: json_headers)

        described_class.new(account, [conversation.display_id]).perform

        expect(WebMock).to have_requested(:post, presence_subscribe_url)
          .with(body: { jids: ['5521999999999@s.whatsapp.net'] }.to_json)
      end

      it 'skips contacts with no identifier or phone' do
        contact.update!(identifier: nil, phone_number: nil)
        expect(whatsapp_channel).not_to receive(:presence_subscribe)
        described_class.new(account, [conversation.display_id]).perform
      end

      it 'limits to 10 conversation IDs' do
        ids = (1..15).to_a
        service = described_class.new(account, ids)
        expect(service.instance_variable_get(:@conversation_ids).length).to eq(10)
      end
    end

    context 'when presence_subscribe is disabled' do
      let(:presence_enabled) { false }

      it 'does not call presence_subscribe' do
        expect(whatsapp_channel).not_to receive(:presence_subscribe)
        described_class.new(account, [conversation.display_id]).perform
      end
    end

    context 'with non-WhatsApp conversations' do
      let(:presence_enabled) { true }
      let(:web_inbox) { create(:inbox, account: account) }
      let(:web_contact) { create(:contact, account: account) }
      let(:web_contact_inbox) { create(:contact_inbox, inbox: web_inbox, contact: web_contact) }
      let!(:web_conversation) do
        create(:conversation, account: account, inbox: web_inbox, contact: web_contact, contact_inbox: web_contact_inbox)
      end

      it 'skips non-WhatsApp conversations' do
        expect(whatsapp_channel).not_to receive(:presence_subscribe)
        described_class.new(account, [web_conversation.display_id]).perform
      end
    end

    context 'with blank conversation_ids' do
      let(:presence_enabled) { true }

      it 'returns early' do
        expect(whatsapp_channel).not_to receive(:presence_subscribe)
        described_class.new(account, []).perform
      end
    end
  end
end
