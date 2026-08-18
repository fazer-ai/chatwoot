require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::MessageRevoked do
  subject(:dispatch) { Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event) }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:conversation) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     content: 'mensagem original', source_id: '3EB0AAAA0001')
  end
  let(:by) { 'contact' }
  let(:event) do
    model::Event.build(
      model::Events::MessageRevoked.new(chat: model::Address.phone('5541999990000'),
                                        message_id: message.source_id, by: by)
    )
  end

  it 'flags a contact revoke without losing the content' do
    expect(dispatch).to eq(:handled)

    expect(message.reload.deleted_by_contact).to be(true)
    expect(message.content).to eq('mensagem original')
  end

  context 'when it was deleted from the connected phone' do
    let(:by) { 'self' }

    it 'marks the message deleted the same way Chatwoot does' do
      expect(dispatch).to eq(:handled)

      expect(message.reload).to be_deleted
      expect(message.content).to eq(I18n.t('conversations.messages.deleted'))
    end

    # The messages controller destroys them, and leaving them behind would keep the
    # deleted media readable through the API and in storage.
    it 'takes the attachments with it' do
      message.attachments.create!(account_id: message.account_id, file_type: :image)

      expect(dispatch).to eq(:handled)
      expect(message.reload.attachments).to be_empty
    end

    it 'ignores the echo of a deletion Chatwoot already applied' do
      message.update!(content: '', content_attributes: message.content_attributes.merge('deleted' => true))

      expect(dispatch).to eq(:ignored)
    end
  end
end
