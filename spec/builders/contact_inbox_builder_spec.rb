require 'rails_helper'

describe ContactInboxBuilder do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, email: 'xyc@example.com', phone_number: '+23423424123', account: account) }

  describe '#perform' do
    describe 'twilio sms inbox' do
      let!(:twilio_sms) { create(:channel_twilio_sms, account: account) }
      let!(:twilio_inbox) { create(:inbox, channel: twilio_sms, account: account) }

      it 'does not create contact inbox when contact inbox already exists with the source id provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: twilio_inbox, source_id: contact.phone_number)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: twilio_inbox,
          source_id: contact.phone_number
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'does not create contact inbox when contact inbox already exists with phone number and source id is not provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: twilio_inbox, source_id: contact.phone_number)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: twilio_inbox
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'creates a new contact inbox when different source id is provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: twilio_inbox, source_id: contact.phone_number)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: twilio_inbox,
          source_id: '+224213223422'
        ).perform

        expect(contact_inbox.id).not_to eq(existing_contact_inbox.id)
        expect(contact_inbox.source_id).to eq('+224213223422')
      end

      it 'creates a contact inbox with contact phone number when source id not provided and no contact inbox exists' do
        contact_inbox = described_class.new(
          contact: contact,
          inbox: twilio_inbox
        ).perform

        expect(contact_inbox.source_id).to eq(contact.phone_number)
      end

      it 'raises error when contact phone number is not present and no source id is provided' do
        contact.update!(phone_number: nil)

        expect do
          described_class.new(
            contact: contact,
            inbox: twilio_inbox
          ).perform
        end.to raise_error(ActionController::ParameterMissing, 'param is missing or the value is empty: contact phone number')
      end
    end

    describe 'twilio whatsapp inbox' do
      let!(:twilio_whatsapp) { create(:channel_twilio_sms, medium: :whatsapp, account: account) }
      let!(:twilio_inbox) { create(:inbox, channel: twilio_whatsapp, account: account) }

      it 'does not create contact inbox when contact inbox already exists with the source id provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: twilio_inbox, source_id: "whatsapp:#{contact.phone_number}")
        contact_inbox = described_class.new(
          contact: contact,
          inbox: twilio_inbox,
          source_id: "whatsapp:#{contact.phone_number}"
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'does not create contact inbox when contact inbox already exists with phone number and source id is not provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: twilio_inbox, source_id: "whatsapp:#{contact.phone_number}")
        contact_inbox = described_class.new(
          contact: contact,
          inbox: twilio_inbox
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'creates a new contact inbox when different source id is provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: twilio_inbox, source_id: "whatsapp:#{contact.phone_number}")
        contact_inbox = described_class.new(
          contact: contact,
          inbox: twilio_inbox,
          source_id: 'whatsapp:+555555'
        ).perform

        expect(contact_inbox.id).not_to eq(existing_contact_inbox.id)
        expect(contact_inbox.source_id).to eq('whatsapp:+555555')
      end

      it 'creates a contact inbox with contact phone number when source id not provided and no contact inbox exists' do
        contact_inbox = described_class.new(
          contact: contact,
          inbox: twilio_inbox
        ).perform

        expect(contact_inbox.source_id).to eq("whatsapp:#{contact.phone_number}")
      end

      it 'raises error when contact phone number is not present and no source id is provided' do
        contact.update!(phone_number: nil)

        expect do
          described_class.new(
            contact: contact,
            inbox: twilio_inbox
          ).perform
        end.to raise_error(ActionController::ParameterMissing, 'param is missing or the value is empty: contact phone number')
      end
    end

    describe 'whatsapp inbox' do
      let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }

      it 'does not create contact inbox when contact inbox already exists with the source id provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: contact.phone_number&.delete('+'))
        contact_inbox = described_class.new(
          contact: contact,
          inbox: whatsapp_inbox,
          source_id: contact.phone_number&.delete('+')
        ).perform

        expect(contact_inbox.id).to be(existing_contact_inbox.id)
      end

      it 'does not create contact inbox when contact inbox already exists with phone number and source id is not provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: contact.phone_number&.delete('+'))
        contact_inbox = described_class.new(
          contact: contact,
          inbox: whatsapp_inbox
        ).perform

        expect(contact_inbox.id).to be(existing_contact_inbox.id)
      end

      it 'creates a new contact inbox when different source id is provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: contact.phone_number&.delete('+'))
        contact_inbox = described_class.new(
          contact: contact,
          inbox: whatsapp_inbox,
          source_id: '555555'
        ).perform

        expect(contact_inbox.id).not_to be(existing_contact_inbox.id)
        expect(contact_inbox.source_id).not_to be('555555')
      end

      it 'creates a contact inbox with contact phone number when source id not provided and no contact inbox exists' do
        contact_inbox = described_class.new(
          contact: contact,
          inbox: whatsapp_inbox
        ).perform

        expect(contact_inbox.source_id).to eq(contact.phone_number&.delete('+'))
      end

      it 'raises error when contact phone number is not present and no source id is provided' do
        contact.update!(phone_number: nil)

        expect do
          described_class.new(
            contact: contact,
            inbox: whatsapp_inbox
          ).perform
        end.to raise_error(ActionController::ParameterMissing, 'param is missing or the value is empty: contact phone number')
      end
    end

    describe 'sms inbox' do
      let!(:sms_channel) { create(:channel_sms, account: account) }
      let!(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }

      it 'does not create contact inbox when contact inbox already exists with the source id provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: sms_inbox, source_id: contact.phone_number)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: sms_inbox,
          source_id: contact.phone_number
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'does not create contact inbox when contact inbox already exists with phone number and source id is not provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: sms_inbox, source_id: contact.phone_number)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: sms_inbox
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'creates a new contact inbox when different source id is provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: sms_inbox, source_id: contact.phone_number)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: sms_inbox,
          source_id: '+224213223422'
        ).perform

        expect(contact_inbox.id).not_to eq(existing_contact_inbox.id)
        expect(contact_inbox.source_id).to eq('+224213223422')
      end

      it 'creates a contact inbox with contact phone number when source id not provided and no contact inbox exists' do
        contact_inbox = described_class.new(
          contact: contact,
          inbox: sms_inbox
        ).perform

        expect(contact_inbox.source_id).to eq(contact.phone_number)
      end

      it 'raises error when contact phone number is not present and no source id is provided' do
        contact.update!(phone_number: nil)

        expect do
          described_class.new(
            contact: contact,
            inbox: sms_inbox
          ).perform
        end.to raise_error(ActionController::ParameterMissing, 'param is missing or the value is empty: contact phone number')
      end
    end

    describe 'email inbox' do
      let!(:email_channel) { create(:channel_email, account: account) }
      let!(:email_inbox) { create(:inbox, channel: email_channel, account: account) }

      it 'does not create contact inbox when contact inbox already exists with the source id provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: email_inbox, source_id: contact.email)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: email_inbox,
          source_id: contact.email
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'does not create contact inbox when contact inbox already exists with email and source id is not provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: email_inbox, source_id: contact.email)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: email_inbox
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'creates a new contact inbox when different source id is provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: email_inbox, source_id: contact.email)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: email_inbox,
          source_id: 'xyc@xyc.com'
        ).perform

        expect(contact_inbox.id).not_to eq(existing_contact_inbox.id)
        expect(contact_inbox.source_id).to eq('xyc@xyc.com')
      end

      it 'creates a contact inbox with contact email when source id not provided and no contact inbox exists' do
        contact_inbox = described_class.new(
          contact: contact,
          inbox: email_inbox
        ).perform

        expect(contact_inbox.source_id).to eq(contact.email)
      end

      it 'raises error when contact email is not present and no source id is provided' do
        contact.update!(email: nil)

        expect do
          described_class.new(
            contact: contact,
            inbox: email_inbox
          ).perform
        end.to raise_error(ActionController::ParameterMissing, 'param is missing or the value is empty: contact email')
      end
    end

    describe 'api inbox' do
      let!(:api_channel) { create(:channel_api, account: account) }
      let!(:api_inbox) { create(:inbox, channel: api_channel, account: account) }

      it 'does not create contact inbox when contact inbox already exists with the source id provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: api_inbox, source_id: 'test')
        contact_inbox = described_class.new(
          contact: contact,
          inbox: api_inbox,
          source_id: 'test'
        ).perform

        expect(contact_inbox.id).to eq(existing_contact_inbox.id)
      end

      it 'creates a new contact inbox when different source id is provided' do
        existing_contact_inbox = create(:contact_inbox, contact: contact, inbox: api_inbox, source_id: SecureRandom.uuid)
        contact_inbox = described_class.new(
          contact: contact,
          inbox: api_inbox,
          source_id: 'test'
        ).perform

        expect(contact_inbox.id).not_to eq(existing_contact_inbox.id)
        expect(contact_inbox.source_id).to eq('test')
      end

      it 'creates a contact inbox with SecureRandom.uuid when source id not provided and no contact inbox exists' do
        contact_inbox = described_class.new(
          contact: contact,
          inbox: api_inbox
        ).perform

        expect(contact_inbox.source_id).not_to be_nil
      end
    end

    describe 'baileys whatsapp inbox phone normalization' do
      let(:baileys_channel) do
        create(:channel_whatsapp, account: account, provider: 'baileys',
                                  sync_templates: false, validate_provider_config: false)
      end
      let(:baileys_inbox) { baileys_channel.inbox }
      let(:contact) { create(:contact, phone_number: '+5511912345678', account: account) }
      let(:canonical_phone) { '+551112345678' }
      let(:canonical_jid) { "#{canonical_phone.delete('+')}@s.whatsapp.net" }

      it 'updates the contact phone when on_whatsapp returns a different canonical jid' do
        allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance
          .with(contact.phone_number)
          .and_return({ 'jid' => canonical_jid, 'exists' => true })

        contact_inbox = described_class.new(
          contact: contact,
          inbox: baileys_inbox,
          validate_baileys_phone: true
        ).perform

        expect(contact.reload.phone_number).to eq(canonical_phone)
        expect(contact_inbox.source_id).to eq(canonical_phone.delete('+'))
      end

      it 'rewrites the caller-provided source_id derived from the pre-normalization phone' do
        allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance
          .and_return({ 'jid' => canonical_jid, 'exists' => true })

        contact_inbox = described_class.new(
          contact: contact,
          inbox: baileys_inbox,
          source_id: '5511912345678',
          validate_baileys_phone: true
        ).perform

        expect(contact_inbox.source_id).to eq(canonical_phone.delete('+'))
      end

      it 'merges into an existing contact when the canonical phone is already taken' do
        existing_contact = create(:contact, name: 'Existing Maria', phone_number: canonical_phone, account: account)
        allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance
          .and_return({ 'jid' => canonical_jid, 'exists' => true })

        contact_inbox = described_class.new(
          contact: contact,
          inbox: baileys_inbox,
          validate_baileys_phone: true
        ).perform

        expect(contact_inbox.contact_id).to eq(existing_contact.id)
        expect(existing_contact.reload.phone_number).to eq(canonical_phone)
        expect { contact.reload }.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotFound') })
      end

      it 'does nothing when on_whatsapp returns the same canonical phone' do
        allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance
          .and_return({ 'jid' => "#{contact.phone_number.delete('+')}@s.whatsapp.net", 'exists' => true })

        expect do
          described_class.new(contact: contact, inbox: baileys_inbox, validate_baileys_phone: true).perform
        end.not_to(change { contact.reload.phone_number })
      end

      it 'does nothing when on_whatsapp reports exists=false' do
        allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance
          .and_return({ 'jid' => canonical_jid, 'exists' => false })

        expect do
          described_class.new(contact: contact, inbox: baileys_inbox, validate_baileys_phone: true).perform
        end.not_to(change { contact.reload.phone_number })
      end

      it 'swallows provider errors and proceeds with the original phone' do
        allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance
          .and_raise(StandardError, 'baileys boom')

        contact_inbox = nil
        expect do
          contact_inbox = described_class.new(contact: contact, inbox: baileys_inbox, validate_baileys_phone: true).perform
        end.not_to(change { contact.reload.phone_number })

        expect(contact_inbox.source_id).to eq(contact.phone_number.delete('+'))
      end

      it 'does not call on_whatsapp when validate_baileys_phone is not requested' do
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance

        described_class.new(contact: contact, inbox: baileys_inbox).perform
      end

      it 'does not call on_whatsapp for whatsapp inboxes on non-baileys providers' do
        non_baileys_inbox = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
        expect_any_instance_of(Channel::Whatsapp).not_to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance

        described_class.new(contact: contact, inbox: non_baileys_inbox, validate_baileys_phone: true).perform
      end
    end

    context 'when there is a race condition' do
      let(:account) { create(:account) }
      let(:contact) { create(:contact, account: account) }
      let(:contact2) { create(:contact, account: account) }
      let(:channel) { create(:channel_email, account: account) }
      let(:channel_api) { create(:channel_api, account: account) }
      let(:source_id) { 'source_123' }

      it 'handles RecordNotUnique error by updating source_id and retrying' do
        existing_contact_inbox = create(:contact_inbox, contact: contact2, inbox: channel.inbox, source_id: source_id)

        described_class.new(
          contact: contact,
          inbox: channel.inbox,
          source_id: source_id
        ).perform

        expect(ContactInbox.last.source_id).to eq(source_id)
        expect(ContactInbox.last.contact_id).to eq(contact.id)
        expect(ContactInbox.last.inbox_id).to eq(channel.inbox.id)
        expect(existing_contact_inbox.reload.source_id).to include(source_id)
        expect(existing_contact_inbox.reload.source_id).not_to eq(source_id)
      end

      it 'does not update source_id for channels other than email or phone number' do
        create(:contact_inbox, contact: contact2, inbox: channel_api.inbox, source_id: source_id)

        expect do
          described_class.new(
            contact: contact,
            inbox: channel_api.inbox,
            source_id: source_id
          ).perform
        end.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end
end
