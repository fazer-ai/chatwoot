require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::MessageReceived do
  subject(:dispatch) { Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event) }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }

  let(:model) { Whatsapp::Session::Model }
  let(:sender) { model::Party.new(phone: '5541999990000', lid: '182736451928374', push_name: 'Ana Souza') }
  let(:chat) { model::Address.phone('5541999990000') }
  let(:content) { model::Content::Text.new(body: 'oi, tudo bem?') }
  let(:inbound) do
    model::InboundMessage.new(
      id: '3EB0AAAA0001', chat: chat, sender: sender, from_me: false,
      timestamp: 1_755_440_000_123, content: content
    )
  end
  let(:event) { model::Event.build(model::Events::MessageReceived.new(message: inbound), epoch: 1, seq: 1) }

  before { allow(channel).to receive(:provider_service).and_return(backend) }

  it 'creates the conversation and the message' do
    expect(dispatch).to eq(:handled)

    message = inbox.messages.find_by(source_id: '3EB0AAAA0001')
    expect(message.content).to eq('oi, tudo bem?')
    expect(message.message_type).to eq('incoming')
    expect(message.content_attributes['external_created_at']).to eq(1_755_440_000)
    expect(message.conversation).to eq(inbox.conversations.last)
  end

  # The Baileys and Z-API writers both acknowledge every incoming row, which is what puts
  # the second tick on the contact's screen and, when the inbox asks for it, marks the
  # chat read. Without it every message this layer stores stays unread on their phone.
  # `any_instance` because the writer reaches the channel through the conversation's own
  # inbox, which is a different object than the one this spec holds.
  it 'tells the provider the message was received' do
    # `any_instance` because the writer reaches the channel through the conversation's
    # own inbox, which is a different object than the one this spec holds.
    expect_any_instance_of(Channel::Whatsapp).to receive(:received_messages) # rubocop:disable RSpec/AnyInstance

    dispatch
  end

  it 'says nothing to the provider about a message the phone itself sent' do
    expect_any_instance_of(Channel::Whatsapp).not_to receive(:received_messages) # rubocop:disable RSpec/AnyInstance

    Whatsapp::Session::Inbound::Dispatcher.dispatch(
      channel,
      model::Event.build(model::Events::MessageReceived.new(
                           message: model::InboundMessage.new(id: '3EB0ECHO01', chat: chat, sender: nil, from_me: true,
                                                              timestamp: 1_755_440_000_123, content: content)
                         ))
    )
  end

  it 'creates the contact behind the message' do
    dispatch

    contact = inbox.messages.find_by(source_id: '3EB0AAAA0001').sender
    expect(contact.name).to eq('Ana Souza')
    expect(contact.phone_number).to eq('+5541999990000')
    expect(contact.identifier).to eq('182736451928374@lid')
    # The LID is what WhatsApp echoes back, so it is what the contact_inbox is keyed by.
    expect(inbox.contact_inboxes.pluck(:source_id)).to contain_exactly('182736451928374')
  end

  it 'reuses the open conversation of the contact' do
    dispatch
    conversation = inbox.conversations.last

    second = inbound.with(id: '3EB0AAAA0002')
    described_class.new(channel: channel, event: model::Event.build(model::Events::MessageReceived.new(message: second))).perform

    expect(inbox.conversations.count).to eq(1)
    expect(conversation.messages.pluck(:source_id)).to include('3EB0AAAA0001', '3EB0AAAA0002')
  end

  it 'answers :duplicate when the message is already stored' do
    expect(dispatch).to eq(:handled)

    expect(Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)).to eq(:duplicate)
    expect(inbox.messages.where(source_id: '3EB0AAAA0001').count).to eq(1)
  end

  it 'links the quoted message and backfills the referral on the conversation it reuses' do
    dispatch
    quoted = inbox.messages.find_by(source_id: '3EB0AAAA0001')

    quoting = inbound.with(id: '3EB0AAAA0003', quoted_id: '3EB0AAAA0001',
                           referral: { 'source_type' => 'ad', 'title' => 'Promo' })
    described_class.new(channel: channel, event: model::Event.build(model::Events::MessageReceived.new(message: quoting))).perform

    message = inbox.messages.find_by(source_id: '3EB0AAAA0003')
    expect(message.content_attributes['in_reply_to_external_id']).to eq('3EB0AAAA0001')
    expect(message.content_attributes['in_reply_to']).to eq(quoted.id)
    expect(inbox.conversations.last.additional_attributes['referral']).to include('title' => 'Promo')
  end

  context 'when the message came from the connected phone' do
    let(:inbound) do
      model::InboundMessage.new(
        id: '3EB0BBBB0001', chat: chat, sender: nil, from_me: true,
        timestamp: 1_755_440_000_123, content: content
      )
    end

    it 'stores it as an outgoing message without an agent' do
      expect(dispatch).to eq(:handled)

      message = inbox.messages.find_by(source_id: '3EB0BBBB0001')
      expect(message.message_type).to eq('outgoing')
      expect(message.sender).to be_nil
      expect(message.content_attributes['external_sender_name']).to eq('WhatsApp')
      expect(inbox.contacts.first.phone_number).to eq('+5541999990000')
    end

    it 'confirms the message Chatwoot had already reserved instead of storing a second one' do
      contact = create(:contact, account: channel.account, phone_number: '+5541999990000')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5541999990000')
      conversation = create(:conversation, contact: contact, contact_inbox: contact_inbox, inbox: inbox,
                                           account: channel.account)
      reserved = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                  message_type: :outgoing, source_id: nil,
                                  content_attributes: { pending_source_id: '3EB0BBBB0001' })

      expect(dispatch).to eq(:handled)

      expect(reserved.reload.source_id).to eq('3EB0BBBB0001')
      expect(conversation.messages.count).to eq(1)
    end
  end

  context 'with media' do
    let(:content) do
      model::Content::Media.new(
        kind: 'image', mime: 'image/jpeg', caption: 'olha isso', filename: 'foto.jpg',
        ref: model::MediaRef.url('https://connector.test/media/abc')
      )
    end

    it 'stores the caption and hands the download to a job' do
      expect(dispatch).to eq(:handled)

      message = inbox.messages.find_by(source_id: '3EB0AAAA0001')
      expect(message.content).to eq('olha isso')
      expect(Whatsapp::Session::MediaFetchJob).to have_been_enqueued
        .with(message, hash_including('kind' => 'image'), hash_including('kind' => 'phone'))
    end

    # The row is committed before the job is queued, so an attempt that failed in
    # between (the job transport is its own Redis) leaves a message whose media would
    # never be asked for again: every retry finds the stored source_id and reports a
    # duplicate. The duplicate has to carry the unfinished work.
    it 'queues the download again when a retry finds the message already stored' do
      dispatch
      message = inbox.messages.find_by(source_id: '3EB0AAAA0001')
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect(Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)).to eq(:duplicate)

      expect(Whatsapp::Session::MediaFetchJob).to have_been_enqueued
        .with(message, hash_including('kind' => 'image'), hash_including('kind' => 'phone'))
    end

    it 'leaves the download alone once the bytes are attached' do
      dispatch
      message = inbox.messages.find_by(source_id: '3EB0AAAA0001')
      message.attachments.create!(account_id: inbox.account_id, file_type: :image)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect(Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)).to eq(:duplicate)

      expect(Whatsapp::Session::MediaFetchJob).not_to have_been_enqueued
    end
  end

  # A rich card's header image is the same downloadable reference a plain media message
  # carries, and the bubble renders it: without the fetch the card arrives text-only.
  context 'with a rich card carrying a media header' do
    let(:content) do
      model::Content::Rich.new(
        kind: 'button', title: 'Pedido #4312', body: 'Seu pedido saiu para entrega',
        buttons: [{ 'text' => 'Acompanhar', 'url' => 'https://exemplo.test/4312' }],
        media: model::Content::Media.new(
          kind: 'image', mime: 'image/jpeg', ref: model::MediaRef.url('https://connector.test/media/xyz')
        )
      )
    end

    it 'hands the header download to a job' do
      expect(dispatch).to eq(:handled)

      message = inbox.messages.find_by(source_id: '3EB0AAAA0001')
      expect(message.content_attributes['rich']).to include('title' => 'Pedido #4312')
      expect(Whatsapp::Session::MediaFetchJob).to have_been_enqueued
        .with(message, hash_including('kind' => 'image'), hash_including('kind' => 'phone'))
    end
  end

  # Blocking has to actually stop the messages and the notifications they raise, which
  # is the rule the Cloud path already applies.
  context 'when the contact is blocked' do
    before do
      contact = create(:contact, account: channel.account, phone_number: '+5541999990000', identifier: '182736451928374@lid')
      create(:contact_inbox, inbox: inbox, contact: contact, source_id: '182736451928374')
      contact.update!(blocked: true)
    end

    it 'writes nothing' do
      expect(dispatch).to eq(:ignored)
      expect(inbox.messages).to be_empty
    end

    context 'when it is the echo of a reply typed on the phone' do
      let(:inbound) do
        model::InboundMessage.new(
          id: '3EB0AAAA0002', chat: chat, sender: sender, from_me: true,
          timestamp: 1_755_440_000_123, content: content
        )
      end

      it 'is still stored, so the agent answer does not go missing' do
        expect(dispatch).to eq(:handled)
        expect(inbox.messages.find_by(source_id: '3EB0AAAA0002')).to be_outgoing
      end
    end
  end

  # `Message#human_response?` reads this flag to count a reply typed in the WhatsApp app
  # as a real answer, which is what clears `waiting_since` and records a first response.
  # WhatsApp already has it: the phone is reporting what it sent. Left at the default
  # the agent sees a message stuck on one tick that no receipt will ever move.
  it 'stores a message typed on the phone as delivered' do
    echo = model::InboundMessage.new(
      id: '3EB0DDDD0001', chat: chat, sender: nil, from_me: true,
      timestamp: 1_755_440_000_123, content: content
    )

    Whatsapp::Session::Inbound::Dispatcher.dispatch(
      channel, model::Event.build(model::Events::MessageReceived.new(message: echo))
    )

    expect(inbox.messages.find_by(source_id: '3EB0DDDD0001').status).to eq('delivered')
  end

  context 'with a reply typed on the connected phone' do
    let(:inbound) do
      model::InboundMessage.new(
        id: '3EB0CCCC0001', chat: chat, sender: sender, from_me: true,
        timestamp: 1_755_440_000_123, content: content
      )
    end

    it 'marks the message as an external echo, so it counts as a reply' do
      expect(dispatch).to eq(:handled)

      message = inbox.messages.find_by(source_id: '3EB0CCCC0001')
      expect(message.content_attributes['external_echo']).to be(true)
      expect(message.send(:human_response?)).to be(true)
    end
  end

  # The contract calls the field `display_name`. Reading `name` found nothing, so the
  # card lost its name and a name-only card produced no message at all, leaving the
  # conversation that had just been opened empty.
  context 'with a shared contact card' do
    let(:content) do
      model::Content::Contacts.new(contacts: [{ 'display_name' => 'Carlos Dias', 'phone' => '+55 41 98888-1111' }])
    end

    it 'stores the shared name alongside the number' do
      expect(dispatch).to eq(:handled)

      message = inbox.messages.last
      expect(message.content).to include('Carlos Dias')
      expect(message.attachments.first.meta['firstName']).to eq('Carlos Dias')
    end

    context 'when the card carries only a name' do
      let(:content) { model::Content::Contacts.new(contacts: [{ 'display_name' => 'Carlos Dias' }]) }

      it 'still writes a message instead of an empty conversation' do
        expect(dispatch).to eq(:handled)
        expect(inbox.messages.last.content).to eq('Carlos Dias')
      end
    end

    # Each card was committed on its own, so a later one failing left the earlier rows
    # holding the event's source id and the redelivery was read as a duplicate: the
    # cards that never landed were dropped for good.
    context 'when a later card cannot be saved' do
      let(:content) do
        model::Content::Contacts.new(contacts: [{ 'display_name' => 'Carlos Dias', 'phone' => '+5541988881111' },
                                                { 'display_name' => 'Bruno Lima', 'phone' => '+5541977776666' }])
      end

      before do
        allow_any_instance_of(Message).to receive(:save!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
          raise ActiveRecord::RecordInvalid, original.receiver if original.receiver.content&.start_with?('Bruno Lima')

          original.call(*args)
        end
      end

      it 'stores none of them, so the redelivery can store all of them' do
        expect { dispatch }.to raise_error(ActiveRecord::RecordInvalid)

        expect(inbox.messages).to be_empty
      end
    end

    # The conversation is opened before the cards are read, so a share with nothing to
    # render used to leave an empty thread and no row holding the source id, which meant
    # every redelivery walked the same path again.
    context 'when nothing in the share can be read' do
      let(:content) { model::Content::Contacts.new(contacts: [{ 'vcard' => 'BEGIN:VCARD\nEND:VCARD' }]) }

      it 'stores an unsupported message instead of an empty conversation' do
        expect(dispatch).to eq(:handled)

        message = inbox.messages.last
        expect(message.source_id).to eq(inbound.id)
        expect(message.is_unsupported).to be(true)
      end

      it 'does not process the same event twice' do
        dispatch

        expect { Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event) }
          .not_to change(inbox.messages, :count)
      end
    end

    # Both named fields are optional on the wire, so a share can be nothing but the
    # vCard, and dropping it left a conversation with no message in it.
    context 'when the card carries only a vCard' do
      let(:vcard) do
        "BEGIN:VCARD\nVERSION:3.0\nFN:Carlos Dias\nTEL;type=CELL;waid=5541988881111:+55 41 98888-1111\nEND:VCARD"
      end
      let(:content) { model::Content::Contacts.new(contacts: [{ 'vcard' => vcard }]) }

      it 'reads the name and the number out of it' do
        expect(dispatch).to eq(:handled)

        message = inbox.messages.last
        expect(message.content).to include('Carlos Dias', '+55 41 98888-1111')
        expect(message.attachments.first.file_type).to eq('contact')
      end
    end
  end

  # `GroupConversationHandler#find_or_create_group_conversation` only reuses open and
  # pending rows, so a snoozed group thread, or a resolved one under
  # `lock_to_single_conversation`, used to get a second conversation and split the group.
  context 'with a group message whose thread is not open' do
    let(:chat) { model::Address.group('120363041234567890') }
    let(:inbound) do
      model::InboundMessage.new(id: '3EB0AAAA0002', chat: chat, sender: sender, from_me: false,
                                timestamp: 1_755_440_000_123, content: content)
    end
    let(:group_dispatch) do
      with_modified_env WHATSAPP_GROUPS_ENABLED: 'true' do
        Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)
      end
    end
    let(:group_contact) do
      create(:contact, account: channel.account, identifier: '120363041234567890@g.us', group_type: :group)
    end
    let(:group_contact_inbox) do
      create(:contact_inbox, inbox: inbox, contact: group_contact, source_id: '120363041234567890')
    end
    let!(:existing) do
      create(:conversation, inbox: inbox, account: channel.account, contact: group_contact,
                            contact_inbox: group_contact_inbox, group_type: :group, status: :snoozed)
    end

    it 'reuses the snoozed thread instead of opening a second one' do
      expect { group_dispatch }.not_to change(inbox.conversations, :count)

      expect(inbox.messages.last.conversation_id).to eq(existing.id)
    end

    context 'when the thread was resolved and the inbox locks to a single conversation' do
      before do
        existing.update!(status: :resolved)
        inbox.update!(lock_to_single_conversation: true)
      end

      it 'reuses it too' do
        expect { group_dispatch }.not_to change(inbox.conversations, :count)
      end
    end
  end

  # A provider that assigns its own id cannot take ours, so the echo comes back under an
  # id Chatwoot has never seen and the correlation token is the only thing tying it to
  # the message that was sent.
  context 'with the echo of a send correlated by client_ref' do
    let(:inbound) do
      model::InboundMessage.new(
        id: 'UAZAPI-XYZ', chat: chat, sender: nil, from_me: true,
        timestamp: 1_755_440_000_123, content: content, client_ref: 'cw:4312'
      )
    end

    it 'confirms the message that was sent instead of storing a second one' do
      contact = create(:contact, account: channel.account, phone_number: '+5541999990000')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5541999990000')
      conversation = create(:conversation, contact: contact, contact_inbox: contact_inbox, inbox: inbox,
                                           account: channel.account)
      reserved = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                  message_type: :outgoing, source_id: nil,
                                  content_attributes: { pending_source_id: 'cw:4312' })

      expect(dispatch).to eq(:handled)

      expect(reserved.reload.source_id).to eq('UAZAPI-XYZ')
      expect(conversation.messages.count).to eq(1)
    end
  end

  # WhatsApp may address the 1:1 chat by a LID the peer has no contact_inbox under yet.
  # Resolving the peer first filed that person a second time, and the reservation was
  # then looked for on the wrong contact: the echo was stored again, in a thread of its
  # own, as if an agent had typed it on the phone.
  context 'with the echo of a send whose chat is addressed only by LID' do
    let(:chat) { model::Address.lid('182736451928374') }
    let(:inbound) do
      model::InboundMessage.new(id: '3EB0AAAA0009', chat: chat, sender: nil, from_me: true,
                                timestamp: 1_755_440_000_123, content: content)
    end
    let!(:reserved) do
      contact = create(:contact, account: channel.account, phone_number: '+5541999990000')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5541999990000')
      conversation = create(:conversation, contact: contact, contact_inbox: contact_inbox, inbox: inbox,
                                           account: channel.account)
      create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                       message_type: :outgoing, source_id: nil,
                       content_attributes: { pending_source_id: '3EB0AAAA0009' })
    end

    it 'confirms the message that was sent' do
      expect(dispatch).to eq(:handled)

      expect(reserved.reload.source_id).to eq('3EB0AAAA0009')
    end

    it 'files no second contact and opens no second thread' do
      expect { dispatch }.to not_change(inbox.contact_inboxes, :count).and not_change(inbox.messages, :count)
    end
  end

  # A worker killed between taking the in-flight marker and writing the row leaves the
  # marker behind. Answering ":duplicate" there acknowledges the event and loses the
  # message for good, so a held marker has to be retryable instead.
  context 'when a marker from a killed worker is still held' do
    before { Whatsapp::Session::Inbound::Locks.with_message_lock(inbox, inbound.id) { nil } }

    it 'asks for a retry rather than reporting the message as already stored' do
      allow(Redis::Alfred).to receive(:set).and_return(false)

      expect { dispatch }.to raise_error(Whatsapp::Session::Inbound::Locks::Busy)
    end
  end

  context 'with a chat Chatwoot has no place for' do
    let(:chat) { model::Address.new(kind: 'status', id: 'status') }

    it 'ignores it' do
      expect(dispatch).to eq(:ignored)
      expect(inbox.messages).to be_empty
    end
  end

  context 'with a group message' do
    let(:chat) { model::Address.group('120363041234567890') }

    it 'is ignored while the group capability is off' do
      expect(dispatch).to eq(:ignored)
      expect(inbox.messages).to be_empty
    end

    it 'opens the group conversation and files the sender as a member' do
      with_modified_env WHATSAPP_GROUPS_ENABLED: 'true' do
        expect(dispatch).to eq(:handled)
      end

      group_contact = inbox.contacts.find_by(identifier: '120363041234567890@g.us')
      expect(group_contact).to be_group_type_group
      conversation = group_contact.conversations.last
      expect(conversation.messages.last.content).to eq('oi, tudo bem?')
      expect(conversation.messages.last.sender.identifier).to eq('182736451928374@lid')
      expect(group_contact.group_memberships.active.count).to eq(1)
    end
  end
end
