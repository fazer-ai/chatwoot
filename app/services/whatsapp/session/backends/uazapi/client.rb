# The HTTP side of the `uazapi` provider: one hosted instance, reached with the base URL
# and the instance token the operator pasted into the inbox form.
#
# Everything this class knows about the provider is transport: how to authenticate, what
# a failure means in canonical terms, and how long to wait. Which endpoints exist and
# what their answers mean belongs to the backend.
class Whatsapp::Session::Backends::Uazapi::Client
  # The instance token travels in a header of this name, which is also what the webhook
  # envelope echoes back. It is a credential: it must never reach a log line.
  TOKEN_HEADER = 'token'.freeze

  # Long enough for the provider to reach WhatsApp and come back, short enough that a
  # provider that is simply gone does not hold a Sidekiq thread. Uploads get their own
  # ceiling: `/send/media` fetches the file from us before it answers.
  TIMEOUT = 20
  UPLOAD_TIMEOUT = 60

  # HTTP status -> contract error code, resolved to a class at raise time by
  # `Errors.build`. Codes rather than classes on purpose: a frozen hash of class objects
  # keeps the ones from before the last reload, and a `rescue` in a caller that did
  # reload then fails to match its own error.
  STATUS_CODES = {
    400 => 'invalid_payload',
    401 => 'unauthorized',
    403 => 'unauthorized',
    404 => 'session_not_found',
    # The build we captured answers 405 on endpoints its own docs describe
    # (`/instance/logout`, `/group/invitelink`). That is a capability this instance does
    # not have rather than a bad request, and the difference decides whether the caller
    # gives up or keeps retrying.
    405 => 'unsupported',
    413 => 'media_too_large',
    415 => 'media_too_large',
    429 => 'rate_limited'
  }.freeze

  # Connection-level failures. All of them mean the same thing to a caller: nobody
  # answered, so ask again later.
  TRANSPORT_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
    Errno::ETIMEDOUT, SocketError, OpenSSL::SSL::SSLError, HTTParty::Error
  ].freeze

  attr_reader :base_url, :token

  def initialize(base_url:, token:)
    @base_url = base_url.to_s.chomp('/')
    @token = token.to_s
    raise Whatsapp::Session::Errors::InvalidConfig, 'uazapi inbox has no base url or token' if @base_url.blank? || @token.blank?
  end

  def get(path, query = {})
    request(:get, path, query: query.compact)
  end

  def post(path, body = {}, timeout: TIMEOUT)
    request(:post, path, body: body.compact, timeout: timeout)
  end

  private

  def request(method, path, query: nil, body: nil, timeout: TIMEOUT)
    # `format: :json` rather than trusting the response's own content type: the answer is
    # always JSON, and a gateway that drops the header would otherwise hand every caller a
    # String where the shape it was written against is a Hash.
    options = { headers: headers, timeout: timeout, format: :json }
    options[:query] = query if query.present?
    options[:body] = body.to_json if body.present?

    parse(HTTParty.public_send(method, url(path), **options), path)
  rescue *TRANSPORT_ERRORS => e
    # The class name, never the message: an error raised over a URL is free to quote it,
    # and a quoted URL is one query string away from carrying the token.
    raise Whatsapp::Session::Errors::ProviderUnavailable, "uazapi #{path} did not answer (#{e.class})"
  end

  def url(path)
    "#{base_url}#{path}"
  end

  def headers
    { TOKEN_HEADER => token, 'Content-Type' => 'application/json' }
  end

  # `parsed_response` is whatever HTTParty made of the body: nil for an empty 200, an
  # Array for the endpoints that answer a list. Handed back as it came, since the backend
  # is what knows the shape of each answer.
  def parse(response, path)
    body = response.parsed_response
    return body if response.success?

    raise Whatsapp::Session::Errors.build(code_for(response), "uazapi #{path} answered #{response.code}#{detail(body)}")
  rescue JSON::ParserError
    # A gateway in front of the provider answering with an HTML page, which is what a
    # 502 looks like from most hosts. It is the provider being unreachable, and it must
    # leave this class as one of ours like every other failure does.
    raise Whatsapp::Session::Errors::ProviderUnavailable, "uazapi #{path} answered #{response.code} with a body that is not json"
  end

  # 5xx is the provider being unwell, which is worth another attempt; an unmapped 4xx is
  # this request being wrong, which is not, and the difference is what decides whether an
  # outbound message is retried or marked failed in front of the agent.
  def code_for(response)
    STATUS_CODES[response.code] || (response.code >= 500 ? 'wa_error' : 'invalid_payload')
  end

  # The provider's own message, when it sends one, and only that field. The rest of an
  # error body is echoed request data, and on `/send/*` that includes the file we just
  # uploaded.
  def detail(body)
    message = body.is_a?(Hash) ? body['message'] : nil
    ": #{message}" if message.present?
  end
end
