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
  OPEN_TIMEOUT = 5

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
    Errno::ETIMEDOUT, SocketError, OpenSSL::SSL::SSLError, HTTParty::Error, SsrfFilter::UnresolvedHostname,
    SsrfFilter::TooManyRedirects
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
    payload = body.to_json if body.present?
    status, answer = if SafeFetch.allow_private_network?
                       direct(method, path, query, payload, timeout)
                     else
                       filtered(method, path, query, payload, timeout)
                     end
    parse(status, answer, path)
  rescue *TRANSPORT_ERRORS => e
    # The class name, never the message: an error raised over a URL is free to quote it,
    # and a quoted URL is one query string away from carrying the token.
    raise Whatsapp::Session::Errors::ProviderUnavailable, "uazapi #{path} did not answer (#{e.class})"
  rescue SsrfFilter::Error => e
    # The address this inbox is pointed at is inside the deployment, or is not an address
    # at all. Not retryable and not the provider's fault: somebody has to change the
    # inbox, so it is reported as the configuration error it is.
    raise Whatsapp::Session::Errors::InvalidConfig, "uazapi #{path} is not an address this deployment will call (#{e.class})"
  end

  # The ordinary path. Every address is resolved here and refused unless it is public: the
  # base URL is typed by whoever administers the account, and this method sends that
  # account's credentials to it and hands the answer back to the dashboard. A validation
  # on the literal address cannot cover a name that resolves inward, and it cannot cover a
  # redirect at all, so the filtering belongs at the moment of the call.
  #
  # The token is named as sensitive, which is what keeps a redirect to another origin from
  # carrying it there.
  def filtered(method, path, query, payload, timeout)
    response = SsrfFilter.public_send(
      method, url(path), headers: headers, body: payload, params: query.presence,
                         sensitive_headers: [TOKEN_HEADER], http_options: { open_timeout: OPEN_TIMEOUT, read_timeout: timeout }
    )
    [response.code.to_i, response.body]
  end

  # An operator who has opened the private network is running the instance next to
  # Chatwoot, which is the one case the filter above cannot be asked about: it has no way
  # to be told that this particular private address is the intended one.
  def direct(method, path, query, payload, timeout)
    options = { headers: headers, timeout: timeout }
    options[:query] = query if query.present?
    options[:body] = payload if payload.present?
    response = HTTParty.public_send(method, url(path), **options)
    [response.code, response.body]
  end

  def url(path)
    "#{base_url}#{path}"
  end

  def headers
    { TOKEN_HEADER => token, 'Content-Type' => 'application/json' }
  end

  # Parsed here rather than left to the client library: the answer is always JSON, and a
  # gateway that drops the content type would otherwise hand a caller a String where the
  # shape it was written against is a Hash. nil for an empty 200, an Array for the
  # endpoints that answer a list; handed back as it came, since the backend is what knows
  # the shape of each answer.
  def parse(status, answer, path)
    body = answer.presence && JSON.parse(answer)
    return body if status.between?(200, 299)

    raise Whatsapp::Session::Errors.build(code_for(status), "uazapi #{path} answered #{status}#{detail(body)}")
  rescue JSON::ParserError
    # A gateway in front of the provider answering with an HTML page, which is what a
    # 502 looks like from most hosts. It is the provider being unreachable, and it must
    # leave this class as one of ours like every other failure does.
    raise Whatsapp::Session::Errors::ProviderUnavailable, "uazapi #{path} answered #{status} with a body that is not json"
  end

  # 5xx is the provider being unwell, which is worth another attempt; an unmapped 4xx is
  # this request being wrong, which is not, and the difference is what decides whether an
  # outbound message is retried or marked failed in front of the agent.
  def code_for(status)
    STATUS_CODES[status] || (status >= 500 ? 'wa_error' : 'invalid_payload')
  end

  # The provider's own message, when it sends one, and only that field. The rest of an
  # error body is echoed request data, and on `/send/*` that includes the file we just
  # uploaded.
  def detail(body)
    message = body.is_a?(Hash) ? body['message'] : nil
    ": #{message}" if message.present?
  end
end
