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

    context 'when BSUID identifiers are present' do
      it 'creates a contact and conversation when only BSUID is present' do
        bsuid_params = {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{
                  profile: { name: 'Muhsin', username: 'muhsin' },
                  user_id: 'IN.2081978709342942',
                  parent_user_id: 'IN.ENT.9081726354'
                }],
                messages: [{
                  from_user_id: 'IN.2081978709342942',
                  from_parent_user_id: 'IN.ENT.9081726354',
                  id: 'wamid.cloud-bsuid-only-message',
                  text: { body: 'testing bsuid' },
                  timestamp: '1778579582',
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access

        described_class.new(inbox: whatsapp_channel.inbox, params: bsuid_params).perform

        contact_inbox = whatsapp_channel.inbox.contact_inboxes.find_by!(source_id: 'IN.2081978709342942')
        contact = contact_inbox.contact
        parent_contact_inbox = whatsapp_channel.inbox.contact_inboxes.find_by!(source_id: 'IN.ENT.9081726354')

        expect(whatsapp_channel.inbox.conversations.count).to eq(1)
        expect(whatsapp_channel.inbox.messages.first.content).to eq('testing bsuid')
        expect(contact).to have_attributes(name: 'Muhsin', phone_number: nil)
        expect(contact.additional_attributes).to include(
          'social_whatsapp_user_name' => 'muhsin',
          'social_profiles' => { 'whatsapp' => 'muhsin' }
        )
        expect(parent_contact_inbox.contact).to eq(contact)
      end

      it 'links phone and BSUID source ids to the same contact' do
        phone_with_bsuid_params = {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Muhsin' }, wa_id: '919745786257', user_id: 'IN.2081978709342942' }],
                messages: [{
                  from: '919745786257',
                  from_user_id: 'IN.2081978709342942',
                  id: 'wamid.cloud-phone-bsuid-message',
                  text: { body: 'phone and bsuid' },
                  timestamp: '1778579582',
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access
        bsuid_only_params = {
          phone_number: whatsapp_channel.phone_number,
          object: 'whatsapp_business_account',
          entry: [{
            changes: [{
              value: {
                contacts: [{ profile: { name: 'Muhsin' }, user_id: 'IN.2081978709342942' }],
                messages: [{
                  from_user_id: 'IN.2081978709342942',
                  id: 'wamid.cloud-bsuid-follow-up-message',
                  text: { body: 'bsuid only' },
                  timestamp: '1778579583',
                  type: 'text'
                }]
              }
            }]
          }]
        }.with_indifferent_access

        described_class.new(inbox: whatsapp_channel.inbox, params: phone_with_bsuid_params).perform
        contact_inbox = whatsapp_channel.inbox.contact_inboxes.find_by!(source_id: '919745786257')
        bsuid_contact_inbox = whatsapp_channel.inbox.contact_inboxes.find_by!(source_id: 'IN.2081978709342942')

        expect { described_class.new(inbox: whatsapp_channel.inbox, params: bsuid_only_params).perform }.not_to raise_error
        expect(whatsapp_channel.inbox.contact_inboxes.count).to eq(2)
        expect(whatsapp_channel.inbox.messages.pluck(:content)).to contain_exactly('phone and bsuid', 'bsuid only')
        expect(bsuid_contact_inbox.contact).to eq(contact_inbox.contact)
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
  end

  # WhatsApp Cloud (including coexistence / embedded signup, which the factory
  # configures by default via provider_config['source'] = 'embedded_signup')
  # delivers an in-place edit as a `type: "edit"` message under the `messages`
  # field. Editing flows through the shared base service, so the same coverage
  # applies to both regular cloud and coexistence inboxes.
  describe '#perform with an edited message' do
    after do
      Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
    end

    let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:text_edit_params) { edit_params({ context: { id: 'M0' }, type: 'text', text: { body: 'Edited content' } }) }

    def edit_params(edited_message)
      message = { from: '2423423243', id: 'wamid.EDIT_EVENT_ID', timestamp: '1664799999', type: 'edit',
                  edit: { original_message_id: 'wamid.ORIGINAL_MESSAGE_ID', message: edited_message } }
      value = { contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }], messages: [message] }
      {
        phone_number: whatsapp_channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{ changes: [{ field: 'messages', value: value }] }]
      }.with_indifferent_access
    end

    def create_original_message(content:, content_attributes: {})
      contact = create(:contact, phone_number: '+2423423243', account: whatsapp_channel.account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: '2423423243')
      conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)
      create(:message, conversation: conversation, source_id: 'wamid.ORIGINAL_MESSAGE_ID',
                       content: content, content_attributes: content_attributes)
    end

    context 'when the original message exists' do
      it 'updates the content in place and records the previous content' do
        original = create_original_message(content: 'Original content')

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: text_edit_params).perform
        end.not_to(change { whatsapp_channel.inbox.messages.count })

        original.reload
        expect(original.content).to eq('Edited content')
        expect(original.content_attributes['is_edited']).to be true
        expect(original.content_attributes['previous_content']).to eq('Original content')
      end

      it 'preserves the earliest previous_content across repeated edits' do
        original = create_original_message(content: 'First edit', content_attributes: { is_edited: true, previous_content: 'Original content' })

        described_class.new(inbox: whatsapp_channel.inbox, params: text_edit_params).perform

        original.reload
        expect(original.content).to eq('Edited content')
        expect(original.content_attributes['previous_content']).to eq('Original content')
      end

      it 'updates a media caption edit' do
        original = create_original_message(content: 'Old caption')
        params = edit_params({ type: 'image', image: { id: 'media-id', mime_type: 'image/jpeg', caption: 'New caption' } })

        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform

        original.reload
        expect(original.content).to eq('New caption')
        expect(original.content_attributes['is_edited']).to be true
        expect(original.content_attributes['previous_content']).to eq('Old caption')
      end
    end

    context 'when the original message does not exist' do
      it 'does not create a new message or contact' do
        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: text_edit_params).perform
        end.to not_change(whatsapp_channel.inbox.messages, :count).and not_change(Contact, :count)

        expect(whatsapp_channel.inbox.messages).to be_empty
      end
    end

    context 'when the edit carries no usable content' do
      it 'leaves the original message untouched' do
        original = create_original_message(content: 'Original content')
        params = edit_params({ type: 'text', text: {} })

        described_class.new(inbox: whatsapp_channel.inbox, params: params).perform

        original.reload
        expect(original.content).to eq('Original content')
        expect(original.content_attributes['is_edited']).to be_nil
      end
    end
  end

  # The contact deleting their own message arrives as `type: "revoke"` under the
  # `messages` field. We keep the content visible and only flag deleted_by_contact.
  describe '#perform with a revoked (deleted) message' do
    after do
      Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
    end

    let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:revoke_params) do
      {
        phone_number: whatsapp_channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            field: 'messages',
            value: {
              contacts: [{ profile: { name: 'Sojan Jose' }, wa_id: '2423423243' }],
              messages: [{
                from: '2423423243', id: 'wamid.REVOKE_EVENT_ID', timestamp: '1664799999',
                type: 'revoke', revoke: { original_message_id: 'wamid.ORIGINAL_MESSAGE_ID' }
              }]
            }
          }]
        }]
      }.with_indifferent_access
    end

    def create_original_message(content:)
      contact = create(:contact, phone_number: '+2423423243', account: whatsapp_channel.account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_channel.inbox, source_id: '2423423243')
      conversation = create(:conversation, contact: contact, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox)
      create(:message, conversation: conversation, source_id: 'wamid.ORIGINAL_MESSAGE_ID', content: content)
    end

    context 'when the original message exists' do
      it 'flags it as deleted by the contact while keeping the content' do
        original = create_original_message(content: 'secret message')

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: revoke_params).perform
        end.not_to(change { whatsapp_channel.inbox.messages.count })

        original.reload
        expect(original.content).to eq('secret message')
        expect(original.content_attributes['deleted_by_contact']).to be true
      end
    end

    context 'when the original message does not exist' do
      it 'does not create a new message or contact' do
        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: revoke_params).perform
        end.to not_change(whatsapp_channel.inbox.messages, :count).and not_change(Contact, :count)

        expect(whatsapp_channel.inbox.messages).to be_empty
      end
    end
  end

  describe '#perform with a click-to-WhatsApp ad referral' do
    # The service clears its own dedupe key in an ensure; this is a safety net for
    # any path that bails before the lock, scoped to this inbox so it can't wipe
    # keys other specs are using against the same Redis DB.
    after do
      Redis::Alfred.scan_each(match: "MESSAGE_SOURCE_KEY::#{whatsapp_channel.inbox.id}_*") { |key| Redis::Alfred.delete(key) }
    end

    let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:referral) do
      {
        source_url: 'https://fb.me/abc123', source_id: '120210000000000', source_type: 'ad',
        headline: 'Promo de Inverno', body: '50% OFF em tudo', media_type: 'image',
        image_url: 'https://example.com/ad-thumb.jpg', ctwa_clid: 'ARAaCtwaClid123'
      }
    end

    def referral_params(message)
      {
        phone_number: whatsapp_channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{ changes: [{ value: {
          contacts: [{ profile: { name: 'Lead Anúncio' }, wa_id: '2423423243' }],
          messages: [message]
        } }] }]
      }.with_indifferent_access
    end

    context 'when a text message carries a referral object' do
      it 'persists the referral on the message and the conversation' do
        message = { from: '2423423243', id: 'wamid.ad1', timestamp: '1664799904', type: 'text',
                    text: { body: 'Oi, vi o anúncio' }, referral: referral }

        described_class.new(inbox: whatsapp_channel.inbox, params: referral_params(message)).perform

        created = whatsapp_channel.inbox.messages.last
        expect(created.content).to eq('Oi, vi o anúncio')
        expect(created.content_attributes['referral']).to include(
          'source_type' => 'ad', 'source_id' => '120210000000000', 'source_url' => 'https://fb.me/abc123',
          'ctwa_clid' => 'ARAaCtwaClid123', 'title' => 'Promo de Inverno', 'body' => '50% OFF em tudo',
          'media_type' => 'image', 'thumbnail_url' => 'https://example.com/ad-thumb.jpg'
        )
        expect(created.conversation.additional_attributes['referral']).to include('ctwa_clid' => 'ARAaCtwaClid123')
      end
    end

    context 'when a request_welcome message carries a referral object' do
      it 'is not skipped and creates a renderable message from the ad headline' do
        message = { from: '2423423243', id: 'wamid.welcome1', timestamp: '1664799904', type: 'request_welcome', referral: referral }

        expect do
          described_class.new(inbox: whatsapp_channel.inbox, params: referral_params(message)).perform
        end.to change(whatsapp_channel.inbox.messages, :count).by(1)

        created = whatsapp_channel.inbox.messages.last
        expect(created.content).to eq('Promo de Inverno')
        expect(created.content_attributes['referral']).to include('ctwa_clid' => 'ARAaCtwaClid123')
        expect(created.conversation.additional_attributes['referral']).to include('ctwa_clid' => 'ARAaCtwaClid123')
      end
    end

    context 'when a referral arrives on an existing conversation' do
      it 'backfills missing attribution and preserves the first touch thereafter' do
        plain = { from: '2423423243', id: 'wamid.plain1', timestamp: '1664799904', type: 'text', text: { body: 'oi' } }
        described_class.new(inbox: whatsapp_channel.inbox, params: referral_params(plain)).perform
        conversation = whatsapp_channel.inbox.messages.last.conversation
        expect(conversation.additional_attributes['referral']).to be_nil

        ad = { from: '2423423243', id: 'wamid.ad2', timestamp: '1664799999', type: 'text',
               text: { body: 'agora vi o anúncio' }, referral: referral }
        described_class.new(inbox: whatsapp_channel.inbox, params: referral_params(ad)).perform

        expect(conversation.reload.additional_attributes['referral']).to include('ctwa_clid' => 'ARAaCtwaClid123')

        later_referral = referral.merge(ctwa_clid: 'DIFFERENT_CLID', source_id: '999999999999999')
        later_ad = { from: '2423423243', id: 'wamid.ad3', timestamp: '1664800000', type: 'text',
                     text: { body: 'outro anúncio' }, referral: later_referral }
        described_class.new(inbox: whatsapp_channel.inbox, params: referral_params(later_ad)).perform

        expect(conversation.reload.additional_attributes['referral']).to include('ctwa_clid' => 'ARAaCtwaClid123', 'source_id' => '120210000000000')
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
