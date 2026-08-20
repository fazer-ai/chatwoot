# The `uazapi` provider: a hosted WhatsApp gateway the customer already pays for, reached
# over HTTP. Chatwoot never provisions an instance here and never holds an admin token:
# the operator brings a base URL and an instance token, and this backend drives that one
# instance.
#
# Where the connector answers commands over Redis and pushes canonical events, this one
# calls REST endpoints and receives a webhook that WebhookTranslator turns into the same
# events. Above this class nothing knows the difference.
#
# WHAT IS PROVEN. The endpoints exercised against a live instance on 19/08/2026 are
# `/instance/{connect,disconnect,status,wa_messages_limits}`, `/webhook`, `/send/*`,
# `/message/{react,edit,markread,download,presence}`, `/chat/{check,details}` and
# `/group/{create,list,updateParticipants}`. The rest follow the provider's own docs and
# are confirmed by the end-to-end checklist, not by a recorded response. Two are known
# NOT to exist on that build: `/instance/logout` and `/group/invitelink` both answer 405,
# which is why logging out is a disconnect and why `group_invites` is not declared.
class Whatsapp::Session::Backends::Uazapi::Backend < Whatsapp::Session::Backend
  include Whatsapp::Session::Backends::Uazapi::Backend::Messages
  include Whatsapp::Session::Backends::Uazapi::Backend::Groups

  # A cap on what a single media download may pull into the Rails process. WhatsApp itself
  # stops well below this; the limit is there so a wrong URL cannot fill a disk.
  MAX_MEDIA_BYTES = 100.megabytes

  # The events this inbox asks for. `chats`, `contacts`, `labels` and `history` are the
  # instance's own CRM chatter and are not subscribed: everything Chatwoot needs is in
  # these five.
  WEBHOOK_EVENTS = %w[connection messages messages_update presence groups].freeze

  # Our own sends come back as an echo, and nothing is excluded from the subscription:
  # the echo is the only way to learn that a send whose answer never arrived actually
  # landed. `/send/*` can accept a message and then time out on the way back, and the
  # sender treats that as retryable, so without the echo the retry posts a second copy
  # and the contact reads the same message twice. The echo carries the `track_id` this
  # inbox generated, `EchoMatcher` fills the row's source_id from it, and
  # `Base::SendOnChannelService` then declines to send a message that already has one.
  # A second row is not the risk it looks like either: the same matcher recognizes the
  # echo of a message already stored.
  WEBHOOK_EXCLUDES = [].freeze

  # `instance.status` -> canonical connection. `hibernated` is a paused instance on the
  # provider's side, which for an inbox is the same as being closed.
  CONNECTIONS = {
    'disconnected' => 'close', 'disconnecting' => 'close', 'hibernated' => 'close',
    'connecting' => 'connecting', 'connected' => 'open'
  }.freeze

  # The disconnect reason that means the pairing itself is gone, not just the socket.
  # Anything else the provider reports is a connection that can come back.
  LOGGED_OUT = /401|logged out/i

  class << self
    def provider_key
      'uazapi'
    end

    def capabilities
      Whatsapp::Session::Registry.descriptor('uazapi').capabilities
    end

    # The QR rotates about every 20 seconds and only the first one arrives on the webhook,
    # so an inbox that is not polled sits on a code that stopped working. The account
    # limits are not pushed at all.
    def state_polling?
      true
    end

    # Whether the instance is somebody else's host is not a question its address can
    # answer. A self-hosted one is reached by whatever name the network gives it, from a
    # compose service to an internal FQDN to a plain address, and reading any of those as
    # a signal gets a deployment wrong in one direction or the other. Only whoever set it
    # up knows, so the inbox is asked and its answer is a field on the form.
    #
    # Not the same switch that opens the private network to the SSRF filter: that one is
    # the operator's, in the environment, and this one sits in a form an account
    # administrator can edit. Saying an instance is a neighbour must not be a way of
    # authorizing calls into the deployment.
    def hosted?(channel)
      !ActiveModel::Type::Boolean.new.cast(channel.provider_config['use_internal_host'])
    end

    # The token is what tells two instances apart: on the hosted service they share a base
    # URL and nothing else in the config belongs to them. Digested, because this is written
    # into a job payload and waits in Redis until the job runs, and a credential does not
    # belong there.
    def instance_fingerprint(channel)
      config = channel.provider_config || {}
      return if config['token'].blank?

      Digest::SHA256.hexdigest("#{config['base_url']}\n#{config['token']}")
    end

    # Resolved on every call rather than held in a constant: a constant captured when this
    # file loads keeps the class from before the last reload.
    def translator
      Whatsapp::Session::Backends::Uazapi::WebhookTranslator
    end

    # Shape only, never a request: saving an inbox must not depend on the provider being
    # up, and a wrong token shows up as `invalid_credentials` on the first connect.
    def validate_config(provider_config)
      config = (provider_config || {}).with_indifferent_access
      keys = []
      keys << 'base_url' unless reachable_http_url?(config[:base_url])
      keys << 'token' if config[:token].blank?
      keys
    end

    private

    # The instance address is set by whoever administers the account, and every method on
    # this backend sends that account's credentials to it and puts the answer on the
    # dashboard. An address inside the deployment's own network would turn the inbox form
    # into a way of reading services that were never meant to be reachable from it, so one
    # is refused unless the operator has said the private network is fair game.
    def reachable_http_url?(value)
      return false unless address.http_url?(value)

      SafeFetch.allow_private_network? || !address.url?(value)
    end

    def address = Whatsapp::Session::PrivateAddress
  end

  # Resolved when called, never held in a constant, for the same reason as above.
  def model = Whatsapp::Session::Model
  def commands = Whatsapp::Session::Model::Commands

  def client
    @client ||= Whatsapp::Session::Backends::Uazapi::Client.new(
      base_url: provider_config['base_url'], token: provider_config['token']
    )
  end

  # --- session lifecycle -----------------------------------------------------------

  # The webhook goes up first: registering it after the connect would leave the window
  # where the session opens and its first messages have nowhere to be delivered.
  def connect(command)
    register_webhook
    body = { phone: (command.phone if command.pairing == 'code') }
    connection_state(client.post('/instance/connect', body))
  end

  def disconnect
    client.post('/instance/disconnect')
    nil
  end

  # There is no unpair on this provider: `/instance/logout` answers 405, so the strongest
  # thing available is dropping the connection. The credentials stay on the instance, and
  # a session paired with the wrong number is ended rather than un-paired, which is why
  # the quarantine marker (not the provider) is what keeps that account's chats out.
  def logout
    disconnect
  end

  # A teardown, not a pause: the inbox is being destroyed or converted. The instance itself
  # belongs to the customer and is never deleted from here.
  #
  # The disconnect goes first because it is the fallible half. A conversion that fails on
  # it is rolled back and the inbox stays on this provider, and withdrawing the webhook
  # before finding that out cannot be undone: the inbox would go on serving uazapi while
  # silently receiving nothing until somebody reconnected it. The other order costs
  # nothing, since the webhook is withdrawn best effort anyway.
  def delete_session
    disconnect
    withdraw_webhook
  end

  def release_registration
    withdraw_webhook
  end

  def fetch_connection_state
    connection_state(client.get('/instance/status'))
  end

  # The code comes back in this same answer, but it is not returned: the pairing poll is
  # already running and writes it, and a backend that also wrote state would be the second
  # writer of a record that has exactly one.
  def request_pairing_code(command)
    client.post('/instance/connect', { phone: command.phone })
    nil
  end

  def fetch_account_limits
    limits = client.get('/instance/wa_messages_limits') || {}
    { 'reachout_time_lock' => reachout_time_lock(limits), 'new_chat_cap' => new_chat_cap(limits) }.compact
  end

  # --- presence and contacts -------------------------------------------------------

  # `delay` is how long the provider holds the indicator up. Chatwoot sends a fresh one on
  # every keystroke burst, so a short hold is what keeps the bubble from sticking after
  # the agent stops typing.
  def send_chat_presence(command)
    client.post('/message/presence', { number: number(command.chat), presence: command.state, delay: 3000 })
    nil
  end

  def update_presence(command)
    client.post('/instance/presence', { presence: command.state })
    nil
  end

  def check_numbers(command)
    Array(client.post('/chat/check', { numbers: Array(command.phones) })).map do |entry|
      entry = entry.to_h
      model::NumberCheck.new(
        phone: entry['query'], exists: entry['isInWhatsapp'].present?,
        address: model::Address.parse(entry['lid'].presence || entry['jid'].presence)
      )
    end
  end

  def profile_picture_url(command)
    details = client.post('/chat/details', { number: number(command.party), preview: command.preview }) || {}
    command.preview ? details['imagePreview'].presence || details['image'] : details['image']
  end

  private

  # --- connection --------------------------------------------------------------------

  # Both `/instance/status` and `/instance/connect` answer with the instance under the
  # same key, so one reader serves them.
  def connection_state(response)
    instance = (response.to_h['instance'] || response.to_h).to_h
    connection = CONNECTIONS.fetch(instance['status'].to_s, 'close')
    model::ConnectionState.new(
      connection: connection,
      qr_data_url: (instance['qrcode'].presence if connection == 'connecting'),
      pairing_code: (instance['paircode'].presence if connection == 'connecting'),
      phone_number: (instance['owner'].presence if connection == 'open'),
      error: connection_error(instance, connection)
    )
  end

  # `owner` keeps the previous number for as long as the instance sits disconnected, so a
  # closed state never reports one: taking it at face value would tell the inbox it is
  # paired with a number that is no longer there.
  def connection_error(instance, connection)
    return if connection != 'close'

    'logged_out' if instance['lastDisconnectReason'].to_s.match?(LOGGED_OUT)
  end

  # --- webhook -----------------------------------------------------------------------

  def register_webhook
    client.post('/webhook', webhook_body(enabled: true))
  end

  # Best effort by design: the inbox is being torn down either way, and a provider that
  # is unreachable (or that has already dropped the instance) must not keep a conversion
  # from finishing.
  def withdraw_webhook
    client.post('/webhook', webhook_body(enabled: false))
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.warn("[WHATSAPP SESSION] could not withdraw the uazapi webhook of inbox ##{channel.inbox&.id}: #{e.message}")
  end

  def webhook_body(enabled:)
    {
      url: webhook_url, enabled: enabled, events: WEBHOOK_EVENTS, excludeMessages: WEBHOOK_EXCLUDES,
      addUrlEvents: false, addUrlTypesMessages: false
    }
  end

  # The address this instance can reach us at, which for a hosted one is the public
  # FRONTEND_URL and for a self-hosted neighbour is INTERNAL_HOST_URL: on a closed
  # installation the public address does not resolve there, and an inbox would pair and
  # then never receive an event.
  #
  # The path carries a secret of its own, generated per inbox and never shown. It is not
  # the only check: the body carries the instance token, which the controller compares
  # too, so a URL leaked through a proxy log is not on its own enough to post events into
  # an inbox.
  def webhook_url
    host = ENV.fetch('INTERNAL_HOST_URL', nil) if channel.use_internal_host?
    host = ENV.fetch('FRONTEND_URL', nil) if host.blank?
    "#{host.to_s.chomp('/')}/webhooks/whatsapp/session/uazapi/#{channel.id}/#{provider_config['webhook_verify_token']}"
  end

  # --- limits ------------------------------------------------------------------------

  # Answered in the shape the dashboard banner already reads, which the Baileys layer
  # established. A provider that reports nothing leaves the key out entirely, because the
  # check job treats a missing value as "unknown" and keeps the last one rather than
  # clearing a banner that is legitimately up.
  def reachout_time_lock(limits)
    lock = limits['reachout_timelock']
    return if lock.blank?

    { 'is_active' => lock['active'].present?, 'time_enforcement_ends' => lock['until'].presence }.compact
  end

  def new_chat_cap(limits)
    cap = limits['new_chat_message_capping']
    return if cap.blank?

    {
      'capping_status' => cap['status'].presence, 'total_quota' => cap['total_quota'],
      'used_quota' => cap['used_quota'], 'cycle_end_timestamp' => cap['cycle_end'].presence
    }.compact
  end

  # --- media -------------------------------------------------------------------------

  # Filtered rather than downloaded outright, because this URL is the provider's to
  # choose: it arrives on the webhook or in the answer to `/message/download`, and an
  # instance that is hostile or merely compromised could name a link-local address and
  # have Rails read a cloud metadata endpoint and attach the answer to a conversation.
  # SafeFetch resolves the host and refuses everything that is not public, which is also
  # why an instance self-hosted on a private network needs SAFE_FETCH_ALLOW_PRIVATE_NETWORK.
  #
  # The content type is deliberately not checked: WhatsApp media is whatever a phone can
  # attach, and the type is a label here, not a decision.
  #
  # Copied out of the block because SafeFetch unlinks its tempfile the moment the block
  # returns, and these bytes are attached later, after the caller has taken its lock.
  def fetch(url, mime: nil)
    SafeFetch.fetch(url, max_bytes: MAX_MEDIA_BYTES, validate_content_type: false) do |result|
      file = Tempfile.new('uazapi-media', binmode: true)
      IO.copy_stream(result.tempfile, file)
      file.rewind
      model::MediaPayload.new(io: file, mime: mime.presence || result.content_type, filename: result.filename, size: file.size)
    end
  rescue SafeFetch::FileTooLargeError => e
    raise Whatsapp::Session::Errors::MediaTooLarge, e.message
  rescue SafeFetch::HttpError, SafeFetch::UnsafeUrlError, SafeFetch::InvalidUrlError => e
    # A status is only ever in the message, and only HttpError has one. A server error or
    # a throttle is the host having a bad minute and worth another pass; the rest is the
    # file being gone, or never having been fetchable at all.
    raise Whatsapp::Session::Errors::ProviderUnavailable, "uazapi media fetch failed: #{e.message}" if retryable_media?(e)

    raise Whatsapp::Session::Errors::MediaUnavailable, "uazapi media is gone: #{e.message}"
  rescue SafeFetch::Error, *Whatsapp::Session::Backends::Uazapi::Client::TRANSPORT_ERRORS => e
    # SafeFetch names some transport failures and not others: a host that refuses or
    # resets the connection comes out as the raw system error, which would escape this
    # backend as itself and miss the fetch job's retry policy entirely.
    raise Whatsapp::Session::Errors::ProviderUnavailable, "uazapi media fetch failed: #{e.message}"
  end

  def retryable_media?(error)
    status = error.message.to_i
    status >= 500 || status == 429
  end

  # --- addressing ----------------------------------------------------------------------

  # What the provider's `number` field takes: a bare phone for a person, the full JID for a
  # group, and the LID JID when that is all we know the contact by.
  def number(address)
    return if address.nil?

    address.phone? ? address.id : address.to_jid
  end
end
