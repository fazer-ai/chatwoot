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

  before { allow(inbox.channel).to receive(:provider_service).and_return(backend) }

  it 'attaches the bytes it downloaded' do
    described_class.perform_now(message, media.to_h)

    expect(message.reload.attachments.first).to have_attributes(file_type: 'image')
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

  it 'flags the message when the provider no longer has the bytes' do
    allow(backend).to receive(:download_media).and_raise(Whatsapp::Session::Errors::MediaUnavailable)

    described_class.perform_now(message, media.to_h)

    expect(message.reload.is_unsupported).to be(true)
  end
end
