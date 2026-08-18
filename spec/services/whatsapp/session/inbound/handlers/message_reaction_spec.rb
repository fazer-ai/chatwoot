require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::MessageReaction do
  subject(:dispatch) { Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event) }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:contact) { create(:contact, account: channel.account, phone_number: '+5541999990000', identifier: '182736451928374@lid') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '182736451928374') }
  let(:conversation) { create(:conversation, contact: contact, contact_inbox: contact_inbox, inbox: inbox, account: channel.account) }
  let(:target) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     message_type: :outgoing, source_id: '3EB0TARGET')
  end
  let(:sender) { model::Party.new(phone: '5541999990000', lid: '182736451928374', push_name: 'Ana Souza') }
  let(:emoji) { '👍' }
  let(:reaction) do
    model::Events::MessageReaction.new(
      id: '3EB0REACTION', chat: model::Address.phone('5541999990000'), sender: sender,
      from_me: false, target_id: target.source_id, emoji: emoji, timestamp: 1_755_440_000_123
    )
  end
  let(:event) { model::Event.build(reaction) }

  it 'stores the reaction in the thread of the message it annotates' do
    expect(dispatch).to eq(:handled)

    stored = inbox.messages.find_by(source_id: '3EB0REACTION')
    expect(stored.content).to eq('👍')
    expect(stored.conversation).to eq(conversation)
    expect(stored.content_attributes['is_reaction']).to be(true)
    expect(stored.content_attributes['in_reply_to_external_id']).to eq('3EB0TARGET')
  end

  # WhatsApp gives a changed reaction a new id, so swapping one emoji for another is a
  # fresh event, not an edit. A second row would show both emojis on the bubble and
  # leave one behind when the reaction is taken back.
  it 'replaces a reaction the same sender already left' do
    target
    dispatch

    changed = model::Events::MessageReaction.new(
      id: '3EB0REACTION2', chat: model::Address.phone('5541999990000'), sender: sender,
      from_me: false, target_id: target.source_id, emoji: '❤️', timestamp: 1_755_440_000_456
    )
    Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, model::Event.build(changed))

    rows = conversation.messages.where("(content_attributes#>>'{}')::jsonb->>'is_reaction' = 'true'")
    expect(rows.count).to eq(1)
    expect(rows.first).to have_attributes(content: '❤️', source_id: '3EB0REACTION2')
  end

  # The reaction Chatwoot sent reserved its id, and a lost send response makes the echo
  # arrive under an id we never stored.
  context 'with the echo of a reaction Chatwoot sent' do
    let(:reaction) do
      model::Events::MessageReaction.new(
        id: '3EB0RESERVED', chat: model::Address.phone('5541999990000'), sender: nil,
        from_me: true, target_id: target.source_id, emoji: emoji, timestamp: 1_755_440_000_123
      )
    end

    it 'confirms the reserved row instead of adding a second reaction' do
      reserved = create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                                  message_type: :outgoing, source_id: nil,
                                  content_attributes: { is_reaction: true, pending_source_id: '3EB0RESERVED' })

      expect(dispatch).to eq(:handled)

      expect(reserved.reload.source_id).to eq('3EB0RESERVED')
      expect(conversation.messages.where("(content_attributes#>>'{}')::jsonb->>'is_reaction' = 'true'").count).to eq(1)
    end
  end

  # Resolving a sender creates a Contact, a ContactInbox and an avatar job, and a
  # removal aimed at a message nobody reacted to has nothing to remove.
  context 'with a removal that matches nothing' do
    let(:emoji) { '' }
    let(:reaction) do
      model::Events::MessageReaction.new(
        id: '3EB0REMOVE', chat: model::Address.phone('5541900001111'),
        sender: model::Party.new(phone: '5541900001111'), from_me: false,
        target_id: '3EB0UNKNOWN', emoji: '', timestamp: 1_755_440_000_123
      )
    end

    it 'leaves no contact behind' do
      expect { expect(dispatch).to eq(:ignored) }.not_to change(Contact, :count)
    end
  end

  context 'when the contact takes the reaction back' do
    let(:emoji) { nil }

    before do
      target
      create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                       message_type: :incoming, sender: contact, content: '👍',
                       content_attributes: { is_reaction: true, in_reply_to_external_id: '3EB0TARGET' })
    end

    it 'empties the stored reaction instead of creating a row' do
      expect(dispatch).to eq(:handled)

      removed = inbox.messages.find_by("(content_attributes#>>'{}')::jsonb->>'is_reaction' = 'true'")
      expect(removed.content).to eq('')
      expect(removed.content_attributes['deleted']).to be(true)
    end

    it 'ignores a removal with nothing left to remove' do
      inbox.messages.where("(content_attributes#>>'{}')::jsonb->>'is_reaction' = 'true'")
           .update_all(content: '') # rubocop:disable Rails/SkipsModelValidations

      expect(dispatch).to eq(:ignored)
    end
  end

  # Resolving the peer creates a Contact, a ContactInbox and an avatar job, and a
  # reaction whose target was never stored has nothing to annotate: it used to open a
  # thread of its own to hold a reaction pointing at a message that does not exist.
  context 'when the message it reacts to was never stored' do
    let(:reaction) do
      model::Events::MessageReaction.new(
        id: '3EB0REACTION', chat: model::Address.phone('5541999990000'), sender: sender,
        from_me: false, target_id: '3EB0NEVERSEEN', emoji: emoji, timestamp: 1_755_440_000_123
      )
    end

    it 'drops it instead of inventing a contact and a thread' do
      expect { expect(dispatch).to eq(:ignored) }
        .to not_change(Contact, :count).and not_change(inbox.conversations, :count)
    end
  end

  context 'when the reaction was made on the connected phone' do
    let(:emoji) { nil }
    let(:reaction) do
      model::Events::MessageReaction.new(
        id: '3EB0REACTION', chat: model::Address.phone('5541999990000'), sender: nil,
        from_me: true, target_id: target.source_id, emoji: nil, timestamp: 1_755_440_000_123
      )
    end

    before do
      target
      # :bot_message is the factory trait for an outgoing message with no agent behind it,
      # which is how a reaction made on the connected phone is stored.
      create(:message, :bot_message, conversation: conversation, inbox: inbox, account: channel.account,
                                     content: '👍', content_attributes: { is_reaction: true, in_reply_to_external_id: '3EB0TARGET' })
    end

    it 'removes the agent-less reaction row' do
      expect(dispatch).to eq(:handled)

      removed = inbox.messages.where(message_type: :outgoing)
                     .find_by("(content_attributes#>>'{}')::jsonb->>'is_reaction' = 'true'")
      expect(removed.content_attributes['deleted']).to be(true)
    end
  end
end
