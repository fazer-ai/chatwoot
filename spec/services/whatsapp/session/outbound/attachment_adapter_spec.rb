require 'rails_helper'

RSpec.describe Whatsapp::Session::Outbound::AttachmentAdapter do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:message) { create(:message, :with_attachment, account: channel.account, inbox: channel.inbox) }
  let(:attachment) { message.attachments.first }

  it 'describes the file in the terms the protocol uses' do
    media = described_class.new(attachment, caption: 'segue a foto', channel: channel).perform

    expect(media.kind).to eq('image')
    expect(media.caption).to eq('segue a foto')
    expect(media.ref.url).to be_present
  end

  # `download_url` rewrites the blob of an `.ogg` recorded as `audio/opus`, which is the
  # shape the fork's own transcode pipeline produces. Reading the type before that runs
  # leaves the media and its ref advertising different ones, and the type is what decides
  # whether WhatsApp plays it as a voice note.
  it 'advertises one MIME type for a voice note whose blob is normalized on the way out' do
    attachment.file.blob.update!(content_type: 'audio/opus', filename: 'gravacao.ogg')
    attachment.update!(file_type: :audio, meta: { 'is_voice_message' => true })

    media = described_class.new(attachment.reload, channel: channel).perform

    expect(media.mime).to eq('audio/ogg')
    expect(media.ref.mime).to eq(media.mime)
    expect(media.voice_note).to be(true)
  end

  describe 'the address the provider is told to fetch from' do
    let(:disk_url) { 'http://localhost:3000/rails/active_storage/disk/TOKEN/avatar.png' }

    before { allow(attachment).to receive(:download_url).and_return(disk_url) }

    it 'is the public one until the inbox says the provider cannot reach it' do
      expect(described_class.new(attachment, channel: channel).media_url).to eq(disk_url)
    end

    it 'moves to the internal host for a provider sitting on a private network' do
      with_modified_env INTERNAL_HOST_URL: 'http://rails:3000' do
        expect(described_class.new(attachment, channel: channel).media_url)
          .to eq('http://rails:3000/rails/active_storage/disk/TOKEN/avatar.png')
      end
    end

    # INTERNAL_HOST_URL is one address for the whole deployment, and a hosted provider is
    # on the far side of the network it points into. An installation running a connector
    # next to a hosted inbox would otherwise hand that inbox a host it cannot resolve, and
    # every attachment it sent would fail with nothing pointing at the setting.
    it 'leaves a hosted provider on the public host even where an internal one is set' do
      hosted = create(:channel_whatsapp, provider: 'uazapi', validate_provider_config: false, sync_templates: false)

      with_modified_env INTERNAL_HOST_URL: 'http://rails:3000' do
        expect(described_class.new(attachment, channel: hosted).media_url).to eq(disk_url)
      end
    end

    # The other side of the same rule: an instance the operator runs next to Chatwoot is a
    # neighbour, and on a closed installation the public URL is the one it cannot reach.
    it 'uses the internal host for an instance that is inside the deployment' do
      neighbour = create(:channel_whatsapp, provider: 'uazapi', validate_provider_config: false, sync_templates: false,
                                            provider_config: { 'base_url' => 'https://uazapi.test', 'token' => 'x',
                                                               'use_internal_host' => true })

      with_modified_env INTERNAL_HOST_URL: 'http://rails:3000' do
        expect(described_class.new(attachment, channel: neighbour).media_url)
          .to eq('http://rails:3000/rails/active_storage/disk/TOKEN/avatar.png')
      end
    end

    # With S3, GCS or any other cloud service the blob answers a presigned URL of its
    # own. Its path is not one Rails serves and its signature is bound to the host it was
    # made for, so moving it to the internal host is a 404 on every attachment the inbox
    # ever sends: the storage is reachable over the internet anyway.
    it 'leaves a presigned cloud-storage URL where it is' do
      url = 'https://bucket.s3.sa-east-1.amazonaws.com/xg7/avatar.png?X-Amz-Signature=deadbeef'
      allow(attachment).to receive(:download_url).and_return(url)

      with_modified_env INTERNAL_HOST_URL: 'http://rails:3000' do
        expect(described_class.new(attachment, channel: channel).media_url).to eq(url)
      end
    end
  end
end
