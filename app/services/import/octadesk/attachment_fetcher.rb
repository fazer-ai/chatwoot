require 'net/http'

# Pulls one attachment off the vendor's bucket and onto ours.
#
# The export carries pointers, not files: hundreds of thousands of URLs on
# storage.googleapis.com under the tenant's own prefix, served without authentication and
# running to hundreds of gigabytes in total. They are reachable
# today and there is no reason to expect them to outlive the subscription, so every import
# run that touches an attachment is also the only chance to keep it. Active Storage writes
# the copy to our S3, which makes the mirror a side effect of the import rather than a
# second project.
#
# No daily budget here, unlike the IMAP path: this is an ordinary bucket over HTTPS, and
# the only limits are our own bandwidth and patience.
class Import::Octadesk::AttachmentFetcher
  TIMEOUT = 30
  MAX_BYTES = 40.megabytes
  # A vendor bucket and nothing else. The URL comes out of a data file, so it is input:
  # without this an edited export could point the fetcher at an internal address.
  ALLOWED_HOST = 'storage.googleapis.com'.freeze

  def initialize(message:, url:, name: nil)
    @message = message
    @url = url
    @name = name
  end

  def perform
    uri = URI.parse(@url)
    return unless uri.is_a?(URI::HTTPS) && uri.host == ALLOWED_HOST

    body = fetch(uri)
    return if body.blank?

    attachment = @message.attachments.new(account_id: @message.account_id, file_type: file_type(body))
    attachment.file.attach(io: StringIO.new(body), filename: filename(uri), content_type: @content_type)
    @message.save!
  end

  private

  def fetch(uri)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.get(uri.request_uri)
    end
    return unless response.is_a?(Net::HTTPSuccess)
    # Capped rather than streamed: the largest measured is under 7 MB, and a cap keeps one
    # malformed record from pulling a gigabyte into memory.
    return if response.body.bytesize > MAX_BYTES

    @content_type = response['content-type'].to_s.split(';').first
    response.body
  end

  def filename(uri)
    @name.presence&.tr('/', '_') || File.basename(uri.path)
  end

  # Falls back on the declared type, then on the extension, which is what the mail
  # pipeline's FileTypeHelper does with an attachment whose headers say nothing useful.
  def file_type(_body)
    helper = Class.new { include FileTypeHelper }.new
    helper.file_type(@content_type)
  end
end
