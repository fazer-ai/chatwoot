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
