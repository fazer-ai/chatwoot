# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactInbox do
  describe 'pubsub_token' do
    let(:contact_inbox) { create(:contact_inbox) }

    it 'gets created on object create' do
      obj = contact_inbox
      expect(obj.pubsub_token).not_to be_nil
    end

    it 'does not get updated on object update' do
      obj = contact_inbox
      old_token = obj.pubsub_token
      obj.update!(source_id: '234234323')
      expect(obj.pubsub_token).to eq(old_token)
    end

    it 'backfills pubsub_token on call for older objects' do
      obj = create(:contact_inbox)
      # to replicate an object with out pubsub_token
      # rubocop:disable Rails/SkipsModelValidations
      obj.update_column(:pubsub_token, nil)
      # rubocop:enable Rails/SkipsModelValidations

      obj.reload

      # ensure the column is nil in database
      expect(described_class.where(id: obj.id).pick(:pubsub_token)).to be_nil

      new_token = obj.pubsub_token
      obj.update!(source_id: '234234323')
      # the generated token shoul be persisted in db
      expect(obj.pubsub_token).to eq(new_token)
    end
  end

  describe 'validations' do
    context 'when source_id' do
      it 'allows source_id longer than 255 characters for channels without format restrictions' do
        long_source_id = 'a' * 300
        email_inbox = create(:inbox, channel: create(:channel_email))
        contact = create(:contact, account: email_inbox.account)
        contact_inbox = build(:contact_inbox, contact: contact, inbox: email_inbox, source_id: long_source_id)

        expect(contact_inbox.valid?).to be(true)
        expect { contact_inbox.save! }.not_to raise_error
        expect(contact_inbox.reload.source_id).to eq(long_source_id)
        expect(contact_inbox.source_id.length).to eq(300)
      end

      it 'validates whatsapp channel source_id' do
        whatsapp_inbox = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false).inbox
        contact = create(:contact)
        valid_source_id = build(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: '1234567890')
        valid_bsuid_source_id = build(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342942')
        valid_parent_bsuid_source_id = build(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.ENT.9081726354')
        ci_character_in_source_id = build(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: '1234567890aaa')
        ci_plus_in_source_id = build(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: '+1234567890')
        expect(valid_source_id.valid?).to be(true)
        expect(valid_bsuid_source_id.valid?).to be(true)
        expect(valid_parent_bsuid_source_id.valid?).to be(true)
        expect(ci_character_in_source_id.valid?).to be(false)
        expect(ci_character_in_source_id.errors.full_messages).to eq(
          ["Source invalid source id for whatsapp inbox. valid Regex #{RegexHelper::WHATSAPP_CHANNEL_REGEX}"]
        )
        expect(ci_plus_in_source_id.valid?).to be(false)
        expect(ci_plus_in_source_id.errors.full_messages).to eq(
          ["Source invalid source id for whatsapp inbox. valid Regex #{RegexHelper::WHATSAPP_CHANNEL_REGEX}"]
        )
      end

      it 'validates twilio sms channel source_id' do
        twilio_sms_inbox = create(:channel_twilio_sms).inbox
        contact = create(:contact)
        valid_source_id = build(:contact_inbox, contact: contact, inbox: twilio_sms_inbox, source_id: '+1234567890')
        ci_character_in_source_id = build(:contact_inbox, contact: contact, inbox: twilio_sms_inbox, source_id: '+1234567890aaa')
        ci_without_plus_in_source_id = build(:contact_inbox, contact: contact, inbox: twilio_sms_inbox, source_id: '1234567890')
        expect(valid_source_id.valid?).to be(true)
        expect(ci_character_in_source_id.valid?).to be(false)
        expect(ci_character_in_source_id.errors.full_messages).to eq(
          ["Source invalid source id for twilio sms inbox. valid Regex #{RegexHelper::TWILIO_CHANNEL_SMS_REGEX}"]
        )
        expect(ci_without_plus_in_source_id.valid?).to be(false)
        expect(ci_without_plus_in_source_id.errors.full_messages).to eq(
          ["Source invalid source id for twilio sms inbox. valid Regex #{RegexHelper::TWILIO_CHANNEL_SMS_REGEX}"]
        )
      end

      it 'validates twilio whatsapp channel source_id' do
        twilio_whatsapp_inbox = create(:channel_twilio_sms, medium: :whatsapp).inbox
        contact = create(:contact)
        valid_source_id = build(:contact_inbox, contact: contact, inbox: twilio_whatsapp_inbox, source_id: 'whatsapp:+1234567890')
        valid_bsuid_source_id = build(:contact_inbox, contact: contact, inbox: twilio_whatsapp_inbox, source_id: 'whatsapp:IN.2081978709342942')
        valid_parent_bsuid_source_id = build(:contact_inbox, contact: contact, inbox: twilio_whatsapp_inbox, source_id: 'whatsapp:IN.ENT.9081726354')
        ci_character_in_source_id = build(:contact_inbox, contact: contact, inbox: twilio_whatsapp_inbox, source_id: 'whatsapp:+1234567890aaa')
        ci_without_plus_in_source_id = build(:contact_inbox, contact: contact, inbox: twilio_whatsapp_inbox, source_id: 'whatsapp:1234567890')
        expect(valid_source_id.valid?).to be(true)
        expect(valid_bsuid_source_id.valid?).to be(true)
        expect(valid_parent_bsuid_source_id.valid?).to be(true)
        expect(ci_character_in_source_id.valid?).to be(false)
        expect(ci_character_in_source_id.errors.full_messages).to eq(
          ["Source invalid source id for twilio whatsapp inbox. valid Regex #{RegexHelper::TWILIO_CHANNEL_WHATSAPP_REGEX}"]
        )
        expect(ci_without_plus_in_source_id.valid?).to be(false)
        expect(ci_without_plus_in_source_id.errors.full_messages).to eq(
          ["Source invalid source id for twilio whatsapp inbox. valid Regex #{RegexHelper::TWILIO_CHANNEL_WHATSAPP_REGEX}"]
        )
      end

      it 'rejects whatsapp BSUID source_id values longer than 128 alphanumeric characters' do
        whatsapp_inbox = create(:channel_whatsapp, sync_templates: false, validate_provider_config: false).inbox
        contact = create(:contact)
        contact_inbox = build(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: "IN.#{'1' * 129}")

        expect(contact_inbox.valid?).to be(false)
      end

      it 'rejects twilio whatsapp parent BSUID source_id values longer than 128 alphanumeric characters' do
        twilio_whatsapp_inbox = create(:channel_twilio_sms, medium: :whatsapp).inbox
        contact = create(:contact)
        contact_inbox = build(:contact_inbox, contact: contact, inbox: twilio_whatsapp_inbox,
                                              source_id: "whatsapp:IN.ENT.#{'1' * 129}")

        expect(contact_inbox.valid?).to be(false)
      end
    end
  end

  # The "no WhatsApp" answer belongs to the phone that was looked up (fazer-ai/chatwoot#877).
  describe 'no-WhatsApp answer and the phone it was about' do
    let(:contact_inbox) { create(:contact_inbox, whatsapp_missing_checked_at: 1.hour.ago) }

    it 'is forgotten when the contact phone is corrected' do
      contact_inbox.contact.update!(phone_number: '+5585911112222')

      expect(contact_inbox.reload.whatsapp_missing_checked_at).to be_nil
    end

    it 'survives edits that leave the phone alone' do
      contact_inbox.contact.update!(name: 'Renamed')

      expect(contact_inbox.reload.whatsapp_missing_checked_at).to be_present
    end

    # The banner reads the conversation, and a contact update only reaches the contacts store.
    it 'tells the dashboard about the conversations it changed' do
      conversation = create(:conversation, contact: contact_inbox.contact, contact_inbox: contact_inbox, inbox: contact_inbox.inbox)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      contact_inbox.contact.update!(phone_number: '+5585911112222')

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_UPDATED, anything, hash_including(conversation: conversation))
    end

    # An older snapshot with an equal updated_at would be kept by the dashboard and bring the
    # warning back.
    it 'moves the conversation version forward with the change' do
      conversation = create(:conversation, contact: contact_inbox.contact, contact_inbox: contact_inbox, inbox: contact_inbox.inbox)
      conversation.update_column(:updated_at, 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { contact_inbox.clear_whatsapp_missing! }.to(change { conversation.reload.updated_at })
    end

    it 'is forgotten when a merge moves the row under another contact' do
      base = create(:contact, account: contact_inbox.contact.account, phone_number: '+5585933334444')

      ContactMergeAction.new(account: base.account, base_contact: base, mergee_contact: contact_inbox.contact).perform

      expect(contact_inbox.reload.contact_id).to eq(base.id)
      expect(contact_inbox.whatsapp_missing_checked_at).to be_nil
    end
  end
end
