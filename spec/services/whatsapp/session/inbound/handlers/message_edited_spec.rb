require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::MessageEdited do
  subject(:dispatch) { Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event) }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:conversation) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     content: 'oi', source_id: '3EB0AAAA0001')
  end
  let(:event) do
    model::Event.build(
      model::Events::MessageEdited.new(
        chat: model::Address.phone('5541999990000'), message_id: message.source_id,
        content: model::Content::Text.new(body: 'oi, corrigido')
      )
    )
  end

  it 'replaces the content and keeps the original' do
    expect(dispatch).to eq(:handled)

    expect(message.reload.content).to eq('oi, corrigido')
    expect(message.is_edited).to be(true)
    expect(message.previous_content).to eq('oi')
  end

  it 'keeps the first version across a second edit' do
    dispatch
    described_class.new(
      channel: channel,
      event: model::Event.build(
        model::Events::MessageEdited.new(
          chat: model::Address.phone('5541999990000'), message_id: message.source_id,
          content: model::Content::Text.new(body: 'terceira versão')
        )
      )
    ).perform

    expect(message.reload.previous_content).to eq('oi')
    expect(message.content).to eq('terceira versão')
  end

  it 'ignores an edit of a message it never stored' do
    event = model::Event.build(
      model::Events::MessageEdited.new(chat: model::Address.phone('5541999990000'), message_id: '3EB0UNKNOWN',
                                       content: model::Content::Text.new(body: 'x'))
    )

    expect(described_class.new(channel: channel, event: event).perform).to eq(:ignored)
  end

  # Removing a caption is a real edit, and dropping it left the old caption on screen
  # with no way to clear it.
  context 'when the edit clears a media caption' do
    let(:event) do
      model::Event.build(
        model::Events::MessageEdited.new(
          chat: model::Address.phone('5541999990000'), message_id: message.source_id,
          content: model::Content::Media.new(kind: 'image', mime: 'image/jpeg', caption: '')
        )
      )
    end

    it 'clears the stored caption' do
      expect(dispatch).to eq(:handled)
      expect(message.reload.content).to eq('')
    end
  end
end
