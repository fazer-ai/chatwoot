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

  # The name an attachment is stored under. On the class because the importer needs the same
  # answer without fetching anything: it is how a second pass tells an attachment it already
  # stored from one it still owes.
  def self.filename_for(url, name)
    name.presence&.tr('/', '_') || File.basename(URI.parse(url.to_s).path)
  rescue URI::InvalidURIError
    name.to_s.tr('/', '_').presence
  end

  private

  # Streamed and abandoned the moment it passes the cap, so an oversized object costs the
  # cap rather than its own size. Reading the response whole and measuring afterwards would
  # have the gigabyte in memory before the check could run, which is the failure the cap
  # was written for and not a thing a cap can undo.
  def fetch(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
        return nil unless response.is_a?(Net::HTTPSuccess)
        return nil if response['content-length'].to_i > MAX_BYTES

        body = read_capped(response)
        return nil if body.nil?

        @content_type = response['content-type'].to_s.split(';').first
        return body
      end
    end
  end

  # Binary from the start: chunks arrive as ASCII-8BIT and appending them to a UTF-8 buffer
  # raises on the first byte that is not valid UTF-8, which for an image is immediately.
  def read_capped(response)
    body = String.new(encoding: Encoding::BINARY)
    response.read_body do |chunk|
      body << chunk
      return nil if body.bytesize > MAX_BYTES
    end
    body
  end

  def filename(uri) = self.class.filename_for(uri, @name)

  # Falls back on the declared type, then on the extension, which is what the mail
  # pipeline's FileTypeHelper does with an attachment whose headers say nothing useful.
  def file_type(_body)
    helper = Class.new { include FileTypeHelper }.new
    helper.file_type(@content_type)
  end
end
