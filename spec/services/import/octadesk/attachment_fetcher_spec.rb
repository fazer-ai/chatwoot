require 'rails_helper'

describe Import::Octadesk::AttachmentFetcher do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:url) { 'https://storage.googleapis.com/tenant/foto.png' }

  # The URL comes out of a data file, so it is input. Without the check an edited export
  # could point the fetcher at an internal address.
  it 'fetches from the vendor bucket and nowhere else' do
    fetcher = described_class.new(message: message, url: 'https://interno.example.com/x.png', name: 'x.png')
    expect(fetcher.perform).to be_nil
    expect(message.attachments).to be_empty
  end

  it 'refuses anything that is not https' do
    expect(described_class.new(message: message, url: 'http://storage.googleapis.com/x.png', name: nil).perform).to be_nil
  end

  it 'stores what it downloads and says so' do
    stub_request(:get, url).to_return(status: 200, body: 'conteudo', headers: { 'content-type' => 'image/png' })
    expect(described_class.new(message: message, url: url, name: 'foto.png').perform).to be_present
    expect(message.reload.attachments.first.file.filename.to_s).to eq('foto.png')
  end

  it 'answers nil when the object is gone, so the caller does not count it as mirrored' do
    stub_request(:get, url).to_return(status: 404)
    expect(described_class.new(message: message, url: url, name: 'foto.png').perform).to be_nil
    expect(message.reload.attachments).to be_empty
  end

  # Reading the response whole and measuring afterwards would have the oversized object in
  # memory before the check could run, which is the failure the cap exists for.
  it 'abandons an object larger than the cap' do
    stub_request(:get, url).to_return(status: 200, body: 'x' * (described_class::MAX_BYTES + 1),
                                      headers: { 'content-type' => 'image/png' })
    expect(described_class.new(message: message, url: url, name: 'foto.png').perform).to be_nil
  end

  describe '.filename_for' do
    it 'prefers the name the export gave' do
      expect(described_class.filename_for(url, 'nota fiscal.pdf')).to eq('nota fiscal.pdf')
    end

    it 'falls back to the last segment of the url' do
      expect(described_class.filename_for(url, nil)).to eq('foto.png')
    end

    it 'keeps a name from becoming a path' do
      expect(described_class.filename_for(url, 'a/b.png')).to eq('a_b.png')
    end
  end

  # A bucket that answers application/octet-stream is answering about every file the same
  # way, and taken at its word it files images, audio and video as :file, which is the one
  # thing the dashboard will not preview.
  describe 'the file type' do
    {
      ['image/jpeg', 'foto.jpg'] => 'image',
      ['application/octet-stream', 'foto.jpg'] => 'image',
      ['application/octet-stream', 'audio.mp3'] => 'audio',
      ['', 'video.mp4'] => 'video',
      ['application/octet-stream', 'doc.pdf'] => 'file',
      ['application/octet-stream', 'sem-extensao'] => 'file'
    }.each do |(content_type, name), expected|
      it "is #{expected} for #{name} declared as #{content_type.presence || 'nothing'}" do
        stub_request(:get, "https://storage.googleapis.com/tenant/#{name}")
          .to_return(status: 200, body: 'x', headers: { 'content-type' => content_type })
        described_class.new(message: message, url: "https://storage.googleapis.com/tenant/#{name}", name: name).perform
        expect(message.reload.attachments.last.file_type).to eq(expected)
      end
    end
  end
end
