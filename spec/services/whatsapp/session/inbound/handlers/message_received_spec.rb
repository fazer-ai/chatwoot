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
      expect(Whatsapp::Session::MediaFetchJob).to have_been_enqueued.with(message, hash_including('kind' => 'image'))
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
      expect(Whatsapp::Session::MediaFetchJob).to have_been_enqueued.with(message, hash_including('kind' => 'image'))
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
