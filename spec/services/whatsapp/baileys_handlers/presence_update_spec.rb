require 'rails_helper'

describe Whatsapp::BaileysHandlers::PresenceUpdate do
  let(:webhook_verify_token) { 'valid_token' }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'baileys',
           provider_config: { webhook_verify_token: webhook_verify_token },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:lid) { '83749283742' }
  let(:phone_number) { '5521999999999' }

  let(:contact) { create(:contact, account: inbox.account, phone_number: "+#{phone_number}", identifier: "#{lid}@lid") }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: lid) }
  let!(:conversation) do
    create(:conversation, account: inbox.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open)
  end

  def perform(data)
    params = { webhookVerifyToken: webhook_verify_token, event: 'presence.update', data: data }
    Whatsapp::IncomingMessageBaileysService.new(inbox: inbox, params: params).perform
  end

  def presence_data_for(lid_jid, status, jid_alt: nil)
    data = {
      id: lid_jid,
      presences: {
        lid_jid => { lastKnownPresence: status }
      }
    }
    data[:jidAlt] = jid_alt if jid_alt
    data
  end

  describe '#process_presence_update' do
    context 'with LID-based JID' do
      let(:jid) { "#{lid}@lid" }

      it 'dispatches CONVERSATION_TYPING_ON for composing' do
        expect(Rails.configuration.dispatcher).to receive(:dispatch)
          .with('conversation.typing_on', anything, hash_including(conversation: conversation, user: contact))
        expect(Rails.configuration.dispatcher).to receive(:dispatch).with('provider.event_received', any_args)

        perform(presence_data_for(jid, 'composing'))
      end

      it 'dispatches CONVERSATION_RECORDING for recording' do
        expect(Rails.configuration.dispatcher).to receive(:dispatch)
          .with('conversation.recording', anything, hash_including(conversation: conversation, user: contact))
        expect(Rails.configuration.dispatcher).to receive(:dispatch).with('provider.event_received', any_args)

        perform(presence_data_for(jid, 'recording'))
      end

      it 'dispatches CONVERSATION_TYPING_OFF for paused' do
        expect(Rails.configuration.dispatcher).to receive(:dispatch)
          .with('conversation.typing_off', anything, hash_including(conversation: conversation, user: contact))
        expect(Rails.configuration.dispatcher).to receive(:dispatch).with('provider.event_received', any_args)

        perform(presence_data_for(jid, 'paused'))
      end

      it 'dispatches CONVERSATION_TYPING_OFF for available' do
        expect(Rails.configuration.dispatcher).to receive(:dispatch)
          .with('conversation.typing_off', anything, hash_including(conversation: conversation, user: contact))
        expect(Rails.configuration.dispatcher).to receive(:dispatch).with('provider.event_received', any_args)

        perform(presence_data_for(jid, 'available'))
      end
    end

    context 'with phone-only contact (no LID yet)' do
      let(:phone_only_contact) { create(:contact, account: inbox.account, phone_number: '+5511888888888') }
      let(:phone_ci) { create(:contact_inbox, inbox: inbox, contact: phone_only_contact, source_id: '5511888888888') }

      before do
        create(:conversation, account: inbox.account, inbox: inbox, contact: phone_only_contact,
                              contact_inbox: phone_ci, status: :open)
      end

      it 'finds contact by phone from jidAlt and dispatches typing' do
        new_lid = '999888777666'
        jid = "#{new_lid}@lid"

        allow(Rails.configuration.dispatcher).to receive(:dispatch)
        expect(Rails.configuration.dispatcher).to receive(:dispatch)
          .with('conversation.typing_on', anything, hash_including(user: phone_only_contact))

        perform(presence_data_for(jid, 'composing', jid_alt: '5511888888888:0@s.whatsapp.net'))
      end

      it 'consolidates contact_inbox source_id from phone to LID' do
        new_lid = '999888777666'
        jid = "#{new_lid}@lid"

        allow(Rails.configuration.dispatcher).to receive(:dispatch)
        perform(presence_data_for(jid, 'composing', jid_alt: '5511888888888:0@s.whatsapp.net'))

        expect(phone_ci.reload.source_id).to eq(new_lid)
      end
    end

    it 'does not dispatch when contact is not found' do
      unknown_jid = '999999999@lid'
      expect(Rails.configuration.dispatcher).to receive(:dispatch).with('provider.event_received', any_args)
      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with('conversation.typing_on', any_args)

      perform(presence_data_for(unknown_jid, 'composing'))
    end

    it 'does not dispatch when no active conversation exists' do
      conversation.update!(status: :resolved)
      jid = "#{lid}@lid"

      expect(Rails.configuration.dispatcher).to receive(:dispatch).with('provider.event_received', any_args)
      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with('conversation.typing_on', any_args)

      perform(presence_data_for(jid, 'composing'))
    end

    it 'ignores group JIDs' do
      group_data = {
        id: '123456789@g.us',
        presences: {
          "#{lid}@lid" => { lastKnownPresence: 'composing' }
        }
      }

      expect(Rails.configuration.dispatcher).to receive(:dispatch).with('provider.event_received', any_args)
      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with('conversation.typing_on', any_args)

      perform(group_data)
    end
  end
end
