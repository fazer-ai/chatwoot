require 'rails_helper'

RSpec.describe Whatsapp::Session::MediaFetchJob do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  let(:model) { Whatsapp::Session::Model }
  let(:conversation) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: '3EB0AAAA0001')
  end
  let(:media) do
    model::Content::Media.new(kind: 'image', mime: 'image/jpeg', filename: 'foto.jpg',
                              ref: model::MediaRef.url('https://connector.test/media/abc'))
  end

  before { allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend) }

  it 'attaches the bytes it downloaded' do
    described_class.perform_now(message, media.to_h)

    expect(message.reload.attachments.first).to have_attributes(file_type: 'image')
  end

  # ContactResolver stores the sender's LID as the contact identifier whenever it has
  # one, so a chat rebuilt from the contact addresses a refresh to a chat the message
  # does not live in, and the provider answers that it cannot find it.
  it 'asks with the chat the event carried, not one rebuilt from the contact' do
    conversation.contact.update!(identifier: '167392323834034@lid')
    chat = model::Address.phone('553499503261')

    described_class.perform_now(message, media.to_h, chat.to_h)

    command = backend.commands.last
    expect(command.chat.to_jid).to eq('553499503261@s.whatsapp.net')
    expect(command.message_id).to eq('3EB0AAAA0001')
  end

  it 'asks without a chat when the event carried none' do
    described_class.perform_now(message, media.to_h)

    expect(backend.commands.last.chat).to be_nil
  end

  # The bubble is created before the bytes exist, and adding an attachment changes no
  # column, so `Message#dispatch_update_event` saw an empty `previous_changes` and said
  # nothing: the open dashboard kept showing the empty bubble until a reload.
  it 'tells the open dashboards that the bubble now has its file' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    described_class.perform_now(message, media.to_h)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::MESSAGE_UPDATED, anything, hash_including(message: message)).at_least(:once)
  end

  it 'does nothing for a message that already has one' do
    described_class.perform_now(message, media.to_h)

    expect { described_class.perform_now(message, media.to_h) }.not_to(change { message.reload.attachments.count })
  end

  # The deletion destroys the attachments, and this job runs asynchronously: attaching
  # afterwards would put the supposedly deleted media back in storage and back on the
  # API, which is the whole reason the deletion removed it.
  it 'does not attach to a message deleted while it was queued' do
    message.update!(content_attributes: message.content_attributes.merge('deleted' => true))

    described_class.perform_now(message, media.to_h)

    expect(message.reload.attachments).to be_empty
  end

  # `MESSAGE_UPDATED` only reaches the open thread, so a media-only message left the
  # conversation card in the list showing "no content" until something else touched it.
  it 'refreshes the conversation card so the preview stops being empty' do
    allow(Whatsapp::Session::Inbound::ChatList).to receive(:refresh).and_call_original

    described_class.perform_now(message, media.to_h)

    expect(Whatsapp::Session::Inbound::ChatList).to have_received(:refresh).with(conversation)
  end

  # The file is past the provider's cap, so no retry changes the answer: the agent needs
  # to see the attachment is not coming rather than a bubble that loads forever.
  it 'flags the message when the media is larger than the provider allows' do
    allow(backend).to receive(:download_media).and_raise(Whatsapp::Session::Errors::MediaTooLarge)

    described_class.perform_now(message, media.to_h)

    expect(message.reload.is_unsupported).to be(true)
  end

  it 'flags the message when the provider no longer has the bytes' do
    allow(backend).to receive(:download_media).and_raise(Whatsapp::Session::Errors::MediaUnavailable)

    described_class.perform_now(message, media.to_h)

    expect(message.reload.is_unsupported).to be(true)
  end

  # `is_unsupported` is a content_attributes flag, so writing it off the stale instance
  # this job is holding rewrote the whole hash and undeleted the message.
  it 'does not undelete a message revoked while the download was running' do
    allow(backend).to receive(:download_media) do
      Message.find(message.id).update!(content_attributes: { 'deleted' => true })
      raise Whatsapp::Session::Errors::MediaUnavailable
    end

    described_class.perform_now(message, media.to_h)

    expect(message.reload.content_attributes).to include('deleted' => true, 'is_unsupported' => true)
  end
end
