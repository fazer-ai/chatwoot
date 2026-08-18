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

  it 'does not open a thread for a reaction whose target is unknown' do
    event = model::Event.build(reaction.with(target_id: '3EB0MISSING', id: '3EB0REACTION2'))

    expect(described_class.new(channel: channel, event: event).perform).to eq(:handled)
    expect(inbox.messages.find_by(source_id: '3EB0REACTION2').conversation).to eq(inbox.conversations.last)
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
