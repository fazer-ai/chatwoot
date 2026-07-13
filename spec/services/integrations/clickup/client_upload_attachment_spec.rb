require 'rails_helper'

RSpec.describe Integrations::Clickup::Client do
  # Focused on `upload_attachment` because it's the one code path where our
  # HTTParty use hits multipart quirks — the JSON endpoints are trivial.
  # Homolog surfaced `400 Invalid upload` because the tempfile that
  # ActiveStorage#open yields has no extension, so HTTParty stamped the
  # multipart Content-Disposition with a random extensionless basename and
  # ClickUp refused it. Guard that with a real request assertion (WebMock).
  describe '#upload_attachment' do
    let(:client) { described_class.new(api_key: 'test_key') }
    let(:task_id) { 'CU123' }
    let(:endpoint) { "https://api.clickup.com/api/v2/task/#{task_id}/attachment" }

    it 'sends the file with the original filename in the multipart body' do
      # ActiveStorage#open yields a Tempfile whose basename has NO extension,
      # matching production shape. If we regress by falling back to
      # `io.path.basename` for the filename, this stub will not match.
      Tempfile.create('active-storage-blob-') do |io|
        io.binmode
        io.write('%PDF-1.4 fake bytes')
        io.rewind

        stub_request(:post, endpoint)
          .with { |req| req.body.include?('filename="evidence.pdf"') && req.body.include?('%PDF-1.4 fake bytes') }
          .to_return(status: 200, body: '{"id":"att_1"}', headers: { 'Content-Type' => 'application/json' })

        response = client.upload_attachment(task_id, io: io, filename: 'evidence.pdf')
        expect(response).to eq('id' => 'att_1')
      end
    end

    it 'wraps a 4xx error as ProviderUnavailable so AttachFileJob retries with backoff' do
      Tempfile.create('active-storage-blob-') do |io|
        io.write('data')
        io.rewind

        stub_request(:post, endpoint)
          .to_return(status: 400, body: '{"err":"Invalid upload","ECODE":"UPLOAD_001"}', headers: { 'Content-Type' => 'application/json' })

        expect { client.upload_attachment(task_id, io: io, filename: 'evidence.pdf') }
          .to raise_error(described_class::ProviderUnavailable, /Invalid upload/)
      end
    end

    it 'raises Unauthorized on 401 so AttachFileJob logs orphan and stops retrying' do
      Tempfile.create('active-storage-blob-') do |io|
        io.write('data')
        io.rewind

        stub_request(:post, endpoint).to_return(status: 401, body: '')

        expect { client.upload_attachment(task_id, io: io, filename: 'evidence.pdf') }
          .to raise_error(described_class::Unauthorized)
      end
    end
  end
end
