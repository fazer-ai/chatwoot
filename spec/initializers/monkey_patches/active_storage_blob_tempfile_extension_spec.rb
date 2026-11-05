require 'rails_helper'

# GHSA-v924-7rp8-4mxh: the tempfile handed to ffprobe and libvips keeps the uploaded extension
# only when it denotes the blob's content type.
RSpec.describe ActiveStorageBlobTempfileExtension do
  def blob_for(data:, filename:, content_type:)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: filename, content_type: content_type, identify: false)
  end

  def tempfile_extension_of(blob)
    blob.open { |file| File.extname(file.path) }
  end

  it 'drops an extension the content type does not account for' do
    blob = blob_for(data: 'Import("/etc/passwd")', filename: 'attack.avs', content_type: 'video/mp4')

    expect(tempfile_extension_of(blob)).to eq('')
  end

  it 'drops an extension Marcel does not recognize' do
    blob = blob_for(data: 'Import("/etc/passwd")', filename: 'attack.avs', content_type: 'application/octet-stream')

    expect(tempfile_extension_of(blob)).to eq('')
  end

  it 'drops a video extension from an image blob' do
    blob = blob_for(data: "#EXTM3U\n#EXTINF:1,\nfile:///etc/hostname\n", filename: 'evil.mp4', content_type: 'image/png')

    expect(tempfile_extension_of(blob)).to eq('')
  end

  it 'keeps an extension that matches the media type, ignoring parameters and case' do
    blob = blob_for(data: '<svg/>', filename: 'icon.svg', content_type: 'image/SVG+XML; charset=utf-8')

    expect(tempfile_extension_of(blob)).to eq('.svg')
  end

  it 'keeps the extension of an ordinary voice note' do
    blob = blob_for(data: 'OggS', filename: 'voice.ogg', content_type: 'audio/ogg')

    expect(tempfile_extension_of(blob)).to eq('.ogg')
  end
end
