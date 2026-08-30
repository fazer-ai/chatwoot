require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::MediaDownloadFailed do
  subject(:dispatch) { Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event) }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }

  let(:model) { Whatsapp::Session::Model }
  let(:chat) { model::Address.phone('5541999990000') }
  let(:conversation) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:pending_media) do
    model::Content::Media.new(kind: 'image', mime: 'image/jpeg', filename: 'foto.jpg').to_h
  end
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account,
                     source_id: '3EB0AAAA0001', content_attributes: { 'pending_media' => pending_media })
  end
  let(:failure) do
    model::Events::MediaDownloadFailed.new(
      chat: chat, message_id: message.source_id, reason: reason, recoverable: recoverable
    )
  end
  let(:event) { model::Event.build(failure, epoch: 1, seq: 1) }

  before { allow(channel).to receive(:provider_service).and_return(backend) }

  context 'when the file is gone for good' do
    let(:reason) { 'media_key_expired' }
    let(:recoverable) { false }

    it 'flags the bubble so the agent stops waiting for it' do
      expect(dispatch).to eq(:handled)

      expect(message.reload.content_attributes['is_unsupported']).to be(true)
    end

    it 'asks nobody for the bytes' do
      expect { dispatch }.not_to have_enqueued_job(Whatsapp::Session::MediaFetchJob)
    end
  end

  context "when WhatsApp dropped the file and the sender's phone may still have it" do
    let(:reason) { 'media_off_cdn' }
    let(:recoverable) { true }

    # The whole point of the flag: the bubble is not flagged, so the fetch that follows
    # can still put the attachment in it. Flagging first is what used to make the
    # recovery unreachable, since MediaFetchJob stands down on `is_unsupported`.
    it 'asks for the bytes instead of giving up on them' do
      expect { dispatch }.to have_enqueued_job(Whatsapp::Session::MediaFetchJob)
        .with(message, pending_media, chat.to_h)

      expect(message.reload.content_attributes['is_unsupported']).to be_nil
    end

    # A message published before the writer kept a descriptor, or one that never carried
    # media at all. There is nothing to rebuild an attachment from, so asking would fetch
    # bytes nothing could attach.
    it 'gives up when nothing was kept to fetch with' do
      message.update!(content_attributes: {})

      expect { dispatch }.not_to have_enqueued_job(Whatsapp::Session::MediaFetchJob)
      expect(message.reload.content_attributes['is_unsupported']).to be(true)
    end

    # The bytes arrived by another route while this event was in flight. Flagging the
    # bubble now would say the attachment is missing next to the attachment.
    it 'does nothing for a message that already has its file' do
      message.attachments.create!(account_id: message.account_id, file_type: :image)

      expect(dispatch).to eq(:ignored)
      expect(message.reload.content_attributes['is_unsupported']).to be_nil
    end
  end
end
