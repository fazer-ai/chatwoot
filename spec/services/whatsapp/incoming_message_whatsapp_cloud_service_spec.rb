require 'rails_helper'

describe Whatsapp::IncomingMessageWhatsappCloudService do
  describe '#perform' do
    after do
      Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
    end

    let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:params) do
      {
        phone_number: whatsapp_channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
              messages: [{
                from: '2423423243',
                image: {
                  id: 'b1c68f38-8734-4ad3-b4a1-ef0c10d683',
                  mime_type: 'image/jpeg',
                  sha256: '29ed500fa64eb55fc19dc4124acb300e5dcca0f822a301ae99944db',
                  caption: 'Check out my product!'
                },
                timestamp: '1664799904', type: 'image'
              }]
            }
          }]
        }]
      }.with_indifferent_access
    end

    context 'when valid attachment message params' do
      it 'creates appropriate conversations, message and contacts' do
        stub_media_url_request
        stub_sample_png_request
        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform
        expect_conversation_created
        expect_contact_name
        expect_message_content
        expect_message_has_attachment
      end

      it 'increments reauthorization count if fetching attachment fails' do
        stub_request(
          :get,
          whatsapp_channel.media_url('b1c68f38-8734-4ad3-b4a1-ef0c10d683')
        ).to_return(
          status: 401
        )

        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform
        expect(whatsapp_channel.inbox.conversations.count).not_to eq(0)
        expect(Contact.all.first.name).to eq('Sojan Jose')
        expect(whatsapp_channel.inbox.messages.first.content).to eq('Check out my product!')
        expect(whatsapp_channel.inbox.messages.first.attachments.present?).to be false
        expect(whatsapp_channel.authorization_error_count).to eq(1)
      end
    end

    context 'when document attachment includes an accented filename' do
      let(:document_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
                messages: [{
                  from: '2423423243',
                  document: {
                    id: 'b1c68f38-8734-4ad3-b4a1-ef0c10d683',
                    mime_type: 'application/pdf',
                    filename: 'Currículum café.pdf',
                    caption: 'My résumé'
                  },
                  timestamp: '1664799904', type: 'document'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'preserves the original filename from the payload' do
        stub_media_url_request
        stub_sample_png_request
        described_class.new(inbox: whatsapp_channel.inbox, params: document_params).perform

        attachment = whatsapp_channel.inbox.messages.first.attachments.first
        expect(attachment.file.filename.to_s).to eq('Currículum café.pdf')
      end
    end

    context 'when invalid attachment message params' do
      let(:error_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
                messages: [{
                  from: '2423423243',
                  image: {
                    id: 'b1c68f38-8734-4ad3-b4a1-ef0c10d683',
                    mime_type: 'image/jpeg',
                    sha256: '29ed500fa64eb55fc19dc4124acb300e5dcca0f822a301ae99944db',
                    caption: 'Check out my product!'
                  },
                  errors: [{
                    code: 400,
                    details: 'Last error was: ServerThrottle. Http request error: HTTP response code said error. See logs for details',
                    title: 'Media download failed: Not retrying as download is not retriable at this time'
                  }],
                  timestamp: '1664799904', type: 'image'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'with attachment errors' do
        described_class.new(inbox: whatsapp_channel.inbox, params: error_params).perform
        expect(whatsapp_channel.inbox.conversations.count).not_to eq(0)
        expect(Contact.all.first.name).to eq('Sojan Jose')
        expect(whatsapp_channel.inbox.messages.count).to eq(0)
      end
    end

    context 'when invalid params' do
      it 'will not throw error' do
        described_class.new(inbox: whatsapp_channel.inbox, params: { phone_number: whatsapp_channel.phone_number,
                                                                     object: 'whatsapp_business_account', entry: {} }).perform
        expect(whatsapp_channel.inbox.conversations.count).to eq(0)
        expect(Contact.all.first).to be_nil
        expect(whatsapp_channel.inbox.messages.count).to eq(0)
      end
    end

    context 'when document attachment has filename with spaces' do
      let(:document_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
                messages: [{
                  from: '2423423243',
                  document: {
                    id: 'b1c68f38-8734-4ad3-b4a1-ef0c10d683',
                    mime_type: 'application/pdf',
                    sha256: '29ed500fa64eb55fc19dc4124acb300e5dcca0f822a301ae99944db',
                    filename: 'Sample File Ação.pdf',
                    caption: 'Check this document'
                  },
                  timestamp: '1664799904', type: 'document'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'uses the filename from the message payload instead of Content-Disposition' do
        stub_media_url_request
        stub_request(:get, 'https://chatwoot-assets.local/sample.png').to_return(
          status: 200,
          body: File.read('spec/assets/attachment.pdf'),
          headers: {
            'content-type' => 'application/pdf',
            'content-disposition' =>
              "attachment; filename=Sample_File_Ao.pdf; filename*=utf-8''Sample%20File%20A%C3%A7%C3%A3o.pdf"
          }
        )

        described_class.new(inbox: whatsapp_channel.inbox, params: document_params).perform

        attachment = whatsapp_channel.inbox.messages.first.attachments.first
        expect(attachment).to be_present
        expect(attachment.file.filename.to_s).to eq('Sample File Ação.pdf')
      end
    end

    context 'when dispatching provider events' do
      let(:message_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              field: 'messages',
              value: {
                contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
                messages: [{
                  from: '2423423243',
                  text: { body: 'Hello' },
                  timestamp: '1664799904', type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      before do
        allow(Rails.configuration.dispatcher).to receive(:dispatch)
      end

      it 'dispatches provider_event_received with the webhook field as event type' do
        described_class.new(inbox: whatsapp_channel.inbox, params: message_params).perform

        expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
          'provider.event_received',
          anything,
          hash_including(
            inbox: whatsapp_channel.inbox,
            event: 'messages',
            payload: message_params[:entry][0][:changes][0][:value]
          )
        )
      end

      it 'does not dispatch when processed_params is blank' do
        empty_params = { phone_number: whatsapp_channel.phone_number, object: 'whatsapp_business_account', entry: {} }.with_indifferent_access
        described_class.new(inbox: whatsapp_channel.inbox, params: empty_params).perform

        expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('provider.event_received', anything, anything)
      end
    end

    context 'when message contains referral data' do
      let(:referral_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Mom' }, wa_id: '255718573302', user_id: 'TZ.1040042605869930' }],
                messages: [{
                  referral: {
                    source_url: 'https://fb.me/3TYpooaRT',
                    source_id: '52558118838064',
                    source_type: 'ad',
                    body: 'washa data tu',
                    headline: 'Diana Digital',
                    media_type: 'video',
                    video_url: 'https://www.facebook.com/reel/1438165771395493/',
                    thumbnail_url: 'https://scontent.xx.fbcdn.net/sample.jpg',
                    ctwa_clid: 'AfhcQdP2E4A8wWpeb1FqUzUi',
                    welcome_message: {
                      text: 'Hi! Please let us know how we can help you.'
                    }
                  },
                  from: '255718573302',
                  from_user_id: 'TZ.1040042605869930',
                  id: 'wamid.CTWA_REFERRAL_MESSAGE',
                  timestamp: '1780649766',
                  text: { body: 'Hello nielekeze' },
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'normalizes and persists the referral on the contact message via the parent payload' do
        contacts_referral_params = referral_params.deep_dup
        parent_message = contacts_referral_params.dig(:entry, 0, :changes, 0, :value, :messages, 0)
        parent_message[:type] = 'contacts'
        parent_message.delete(:text)
        parent_message[:contacts] = [{
          name: {
            formatted_name: 'Diana Digital',
            first_name: 'Diana',
            last_name: 'Digital'
          },
          phones: [{ phone: '+255718573302' }]
        }]

        described_class.new(inbox: whatsapp_channel.inbox, params: contacts_referral_params).perform

        message = whatsapp_channel.inbox.messages.last
        expect(message.content).to eq('Diana Digital')
        expect(message.content_attributes['referral']).to include(
          'source_type' => 'ad',
          'source_id' => '52558118838064',
          'ctwa_clid' => 'AfhcQdP2E4A8wWpeb1FqUzUi',
          'title' => 'Diana Digital'
        )
      end
    end

    context 'when message is a reply (has context)' do
      let(:reply_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Pranav' }, wa_id: '16503071063' }],
                messages: [{
                  context: {
                    from: '16503071063',
                    id: 'wamid.ORIGINAL_MESSAGE_ID'
                  },
                  from: '16503071063',
                  id: 'wamid.REPLY_MESSAGE_ID',
                  timestamp: '1770407829',
                  text: { body: 'This is a reply' },
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      context 'when the original message exists in Chatwoot' do
        it 'sets in_reply_to to reference the existing message' do
          # Create a conversation and the original message that will be replied to first
          contact = create(:contact, phone_number: '+16503071063', account: whatsapp_channel.account)
          contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: '16503071063')
          conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)

          original_message = create(:message,
                                    conversation: conversation,
                                    source_id: 'wamid.ORIGINAL_MESSAGE_ID',
                                    content: 'Original message')

          described_class.new(inbox: whatsapp_channel.inbox, params: reply_params).perform

          reply_message = whatsapp_channel.inbox.messages.last
          expect(reply_message.content).to eq('This is a reply')
          expect(reply_message.content_attributes['in_reply_to']).to eq(original_message.id)
          expect(reply_message.content_attributes['in_reply_to_external_id']).to eq('wamid.ORIGINAL_MESSAGE_ID')
        end
      end

      context 'when the original message does not exist in Chatwoot' do
        it 'does not set in_reply_to (discards the reply reference)' do
          described_class.new(inbox: whatsapp_channel.inbox, params: reply_params).perform

          reply_message = whatsapp_channel.inbox.messages.last
          expect(reply_message.content).to eq('This is a reply')
          expect(reply_message.content_attributes['in_reply_to']).to be_nil
          expect(reply_message.content_attributes['in_reply_to_external_id']).to be_nil
        end
      end
    end

    context 'when message is a reaction' do
      let(:reaction_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Gabriel Jablonski' }, wa_id: '553499503261' }],
                messages: [{
                  from: '553499503261',
                  id: 'wamid.REACTION_MESSAGE_ID',
                  timestamp: '1776974260',
                  type: 'reaction',
                  reaction: {
                    message_id: 'wamid.ORIGINAL_MESSAGE_ID',
                    emoji: '❤️'
                  }
                }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      context 'when the reacted message exists in Chatwoot' do
        it 'creates a reaction message linked to the original message' do
          contact = create(:contact, phone_number: '+553499503261', account: whatsapp_channel.account)
          contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: '553499503261')
          conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)
          original_message = create(:message,
                                    conversation: conversation,
                                    source_id: 'wamid.ORIGINAL_MESSAGE_ID',
                                    content: 'Original message')

          described_class.new(inbox: whatsapp_channel.inbox, params: reaction_params).perform

          reaction_message = whatsapp_channel.inbox.messages.find_by(source_id: 'wamid.REACTION_MESSAGE_ID')
          expect(reaction_message).to be_present
          expect(reaction_message.content).to eq('❤️')
          expect(reaction_message.message_type).to eq('incoming')
          expect(reaction_message.attachments).to be_empty
          expect(reaction_message.content_attributes['is_reaction']).to be true
          expect(reaction_message.content_attributes['in_reply_to']).to eq(original_message.id)
          expect(reaction_message.content_attributes['in_reply_to_external_id']).to eq('wamid.ORIGINAL_MESSAGE_ID')
        end
      end

      context 'when the reacted message does not exist in Chatwoot' do
        it 'still creates the reaction message but discards the reply reference' do
          described_class.new(inbox: whatsapp_channel.inbox, params: reaction_params).perform

          reaction_message = whatsapp_channel.inbox.messages.find_by(source_id: 'wamid.REACTION_MESSAGE_ID')
          expect(reaction_message).to be_present
          expect(reaction_message.content).to eq('❤️')
          expect(reaction_message.content_attributes['is_reaction']).to be true
          expect(reaction_message.content_attributes['in_reply_to']).to be_nil
          expect(reaction_message.content_attributes['in_reply_to_external_id']).to be_nil
        end
      end

      context 'when the reaction emoji is blank (reaction removed)' do
        let(:reaction_removal_params) do
          reaction_params.deep_dup.tap do |payload|
            payload[:entry][0][:changes][0][:value][:messages][0][:reaction][:emoji] = ''
          end
        end

        it 'does not create a message' do
          expect do
            described_class.new(inbox: whatsapp_channel.inbox, params: reaction_removal_params).perform
          end.not_to(change { whatsapp_channel.inbox.messages.count })
        end

        it 'marks a matching existing reaction as removed in place' do
          contact = create(:contact, phone_number: '+553499503261', account: whatsapp_channel.account)
          contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: '553499503261')
          conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)
          create(:message, conversation: conversation, source_id: 'wamid.ORIGINAL_MESSAGE_ID', content: 'Original message')
          existing_reaction = create(:message,
                                     conversation: conversation,
                                     sender: contact,
                                     message_type: :incoming,
                                     content: '❤️',
                                     content_attributes: { is_reaction: true,
                                                           in_reply_to_external_id: 'wamid.ORIGINAL_MESSAGE_ID' })

          expect do
            described_class.new(inbox: whatsapp_channel.inbox, params: reaction_removal_params).perform
          end.not_to(change { whatsapp_channel.inbox.messages.count })

          existing_reaction.reload
          expect(existing_reaction.content).to eq('')
          expect(existing_reaction.content_attributes['deleted']).to be true
        end

        it 'dispatches conversation.updated after marking a reaction as removed' do
          contact = create(:contact, phone_number: '+553499503261', account: whatsapp_channel.account)
          contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: '553499503261')
          conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)
          create(:message, conversation: conversation, source_id: 'wamid.ORIGINAL_MESSAGE_ID', content: 'Original message')
          create(:message,
                 conversation: conversation,
                 sender: contact,
                 message_type: :incoming,
                 content: '❤️',
                 content_attributes: { is_reaction: true, in_reply_to_external_id: 'wamid.ORIGINAL_MESSAGE_ID' })
          dispatched = []
          allow_any_instance_of(Conversation).to receive(:dispatch_conversation_updated_event) do |conv| # rubocop:disable RSpec/AnyInstance
            dispatched << conv.id
          end

          described_class.new(inbox: whatsapp_channel.inbox, params: reaction_removal_params).perform

          expect(dispatched).to include(conversation.id)
        end
      end
    end

    # Regression coverage for the duplicate contact_inbox bug. External
    # integrations (pencil create, n8n, CRM import) can stamp a
    # contact_inbox with an off-format source_id that Meta won't accept
    # on outbound — every send then fails with 131026. When the patient
    # eventually messages in via Meta, the webhook lands with the
    # canonical wa_id and the service must consolidate the two ci's so
    # that the conversation can be answered.
    describe 'duplicate contact_inbox consolidation' do
      let(:canonical_waid) { '553197516012' }
      let(:incoming_message_params) do
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              field: 'messages',
              value: {
                contacts: [{ profile: { name: 'Farly' }, wa_id: canonical_waid }],
                messages: [{ from: canonical_waid, text: { body: 'Olá' }, timestamp: '1750100000', type: 'text' }]
              }
            }]
          }]
        }.with_indifferent_access
      end

      it 'merges an off-format contact_inbox onto the canonical wa_id when the patient messages in' do
        # Off-format ci created earlier by an external integration
        # (n8n-style suffix). Has an existing conversation, mirroring
        # the production fingerprint that motivated this fix.
        contact = create(:contact, account: whatsapp_channel.account, name: 'Farly', phone_number: "+#{canonical_waid}")
        off_format_ci = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox,
                                               source_id: "5531997516012-#{whatsapp_channel.inbox.id}")
        legacy_conversation = create(:conversation, account: whatsapp_channel.account, inbox: whatsapp_channel.inbox,
                                                    contact: contact, contact_inbox: off_format_ci)

        described_class.new(inbox: whatsapp_channel.inbox, params: incoming_message_params).perform

        # End state: exactly one ci, with the canonical source_id, and
        # the legacy conversation now points to it.
        cis = whatsapp_channel.inbox.contact_inboxes.where(contact_id: contact.id)
        expect(cis.count).to eq(1)
        expect(cis.first.source_id).to eq(canonical_waid)
        expect(legacy_conversation.reload.contact_inbox_id).to eq(cis.first.id)
      end

      it 'keeps the canonical contact_inbox when the existing one already matches' do
        contact = create(:contact, account: whatsapp_channel.account, name: 'Farly', phone_number: "+#{canonical_waid}")
        canonical_ci = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: canonical_waid)

        described_class.new(inbox: whatsapp_channel.inbox, params: incoming_message_params).perform

        expect(whatsapp_channel.inbox.contact_inboxes.where(contact_id: contact.id).pluck(:id)).to eq([canonical_ci.id])
        expect(canonical_ci.reload.source_id).to eq(canonical_waid)
      end

      it 'is a no-op when only one contact_inbox exists, even if its source_id is off-format' do
        # Defensive: don't rewrite an off-format ci unless there's a
        # second ci to consolidate. The patient may eventually message
        # in and trigger the normal path; we don't want to surprise the
        # operator by silently renaming on every webhook.
        contact = create(:contact, account: whatsapp_channel.account, name: 'Farly', phone_number: "+#{canonical_waid}")
        off_format_ci = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox,
                                               source_id: "5531997516012-#{whatsapp_channel.inbox.id}")

        described_class.new(inbox: whatsapp_channel.inbox, params: incoming_message_params).perform

        # The webhook creates a SECOND ci (with canonical), and now the
        # consolidation kicks in — survivor is canonical, the off-format
        # is merged in. End state: 1 ci with the canonical source_id.
        expect(whatsapp_channel.inbox.contact_inboxes.where(contact_id: contact.id).pluck(:source_id)).to eq([canonical_waid])
        expect(ContactInbox.exists?(id: off_format_ci.id)).to be(false)
      end
    end

    # Regression coverage for out-of-order status acks. Meta retries each
    # status (sent / delivered / read) independently and async deliveries
    # can land an older status after a newer one already arrived — without
    # this guard the checkmark would rewind in the UI.
    describe 'status update ordering' do
      let(:conversation_for_status) do
        create(:conversation, account: whatsapp_channel.account, inbox: whatsapp_channel.inbox)
      end
      let!(:tracked_message) do
        create(:message, account: whatsapp_channel.account, inbox: whatsapp_channel.inbox,
                         conversation: conversation_for_status, source_id: 'wamid.PHBgNTUx', status: :read)
      end

      def status_payload(new_status, errors: nil)
        status_entry = { id: tracked_message.source_id, status: new_status, timestamp: '1664799904',
                         recipient_id: '2423423243' }
        status_entry[:errors] = errors if errors
        {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{ changes: [{ value: { statuses: [status_entry] } }] }]
        }.with_indifferent_access
      end

      it 'ignores a delivered ack that arrives after read' do
        described_class.new(inbox: whatsapp_channel.inbox, params: status_payload('delivered')).perform
        expect(tracked_message.reload.status).to eq('read')
      end

      it 'ignores a sent ack that arrives after delivered' do
        tracked_message.update!(status: :delivered)
        described_class.new(inbox: whatsapp_channel.inbox, params: status_payload('sent')).perform
        expect(tracked_message.reload.status).to eq('delivered')
      end

      it 'still advances forward: sent → delivered → read' do
        tracked_message.update!(status: :sent)
        described_class.new(inbox: whatsapp_channel.inbox, params: status_payload('delivered')).perform
        expect(tracked_message.reload.status).to eq('delivered')

        described_class.new(inbox: whatsapp_channel.inbox, params: status_payload('read')).perform
        expect(tracked_message.reload.status).to eq('read')
      end

      it 'always applies a failed status even when one had already been read' do
        described_class.new(inbox: whatsapp_channel.inbox,
                            params: status_payload('failed', errors: [{ code: 131_026, title: 'Re-engagement message' }])).perform

        expect(tracked_message.reload.status).to eq('failed')
        expect(tracked_message.reload.external_error).to eq('131026: Re-engagement message')
      end
    end
  end

  # Métodos auxiliares para reduzir o tamanho do exemplo

  def stub_media_url_request
    stub_request(
      :get,
      whatsapp_channel.media_url('b1c68f38-8734-4ad3-b4a1-ef0c10d683')
    ).to_return(
      status: 200,
      body: {
        messaging_product: 'whatsapp',
        url: 'https://chatwoot-assets.local/sample.png',
        mime_type: 'image/jpeg',
        sha256: 'sha256',
        file_size: 'SIZE',
        id: 'b1c68f38-8734-4ad3-b4a1-ef0c10d683'
      }.to_json,
      headers: { 'content-type' => 'application/json' }
    )
  end

  def stub_sample_png_request
    stub_request(:get, 'https://chatwoot-assets.local/sample.png').to_return(
      status: 200,
      body: File.read('spec/assets/sample.png')
    )
  end

  def expect_conversation_created
    expect(whatsapp_channel.inbox.conversations.count).not_to eq(0)
  end

  def expect_contact_name
    expect(Contact.all.first.name).to eq('Sojan Jose')
  end

  def expect_message_content
    expect(whatsapp_channel.inbox.messages.first.content).to eq('Check out my product!')
  end

  def expect_message_has_attachment
    expect(whatsapp_channel.inbox.messages.first.attachments.present?).to be true
  end
end
