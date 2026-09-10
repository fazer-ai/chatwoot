# The `native` provider: a session held by the Go connector, reached over Redis.
#
# Every method here is the same shape: build a canonical command, hand it to the client,
# and turn the reply into the canonical object the caller expects. What is fire and
# forget on the wire is fire and forget here too, and its failures come back later as a
# command.failed event rather than as a return value.
class Whatsapp::Session::Backends::Connector::Backend < Whatsapp::Session::Backend
  # A cap on what a single media download may pull into the Rails process. WhatsApp
  # itself stops well below this; the limit is there so a wrong URL cannot fill a disk.
  MAX_MEDIA_BYTES = 100.megabytes

  # How fast a file is assumed to move, end to end, when sizing the wait for a send that
  # carries one. Deliberately pessimistic: the connector has to fetch the file from this
  # app's storage, encrypt it into a temporary file and upload it to WhatsApp before it
  # can answer, and the number that matters is the slowest of those links rather than the
  # one inside the datacentre.
  MEDIA_SEND_RATE = ENV.fetch('WHATSAPP_MEDIA_SEND_RATE_BYTES', 1.megabyte).to_i

  # The ceiling on that wait. A send holds a Redis connection out of the pool and the
  # worker that called it for as long as it runs, so a file too big to move inside this
  # is one this deployment does not send -- and it says so on the deadline rather than by
  # holding a worker indefinitely.
  MEDIA_SEND_MAX_TIMEOUT = ENV.fetch('WHATSAPP_MEDIA_SEND_MAX_TIMEOUT', 180).to_i

  # --- the ceiling on a published command ------------------------------------------
  #
  # A published command carries no `reply_to`, so nobody here is waiting to give up on it,
  # and the `deadline` on its frame is the only limit the connector has for it: it refuses
  # a command whose deadline passed before it was reached, and it bounds the execution of
  # one it does run. The session's executor takes one command at a time, so a published
  # command with no ceiling, parked on a socket write, is every send behind it parked too.
  #
  # How much budget differs by what a late execution would mean, because the one field
  # says "do not start after this" and "do not run longer than this" at the same time.

  # A momentary state that lands late is not late, it is wrong: an `available` applied
  # after the agent went offline flips the account back, and a `composing` applied minutes
  # later is a typing bubble for something nobody is typing.
  MOMENTARY_TIMEOUT = 30

  # These are still right whenever they land, so the only reason to bound them is the
  # executor, and the ceiling has to clear the longest command that can legitimately be
  # ahead of them on the same queue: a send carrying a file. A queue holding several of
  # those back to back can still expire one, and what that costs is a receipt the
  # customer's phone never shows, repaired the next time the same chat is read.
  DEFERRABLE_TIMEOUT = MEDIA_SEND_MAX_TIMEOUT + Whatsapp::Connector::Client::RPC_TIMEOUT

  # A pairing code is worth as long as the attempt that asked for it, which is the ceiling
  # the pairing screen already runs on: past it, the screen the operator would type the
  # code into is gone.
  PAIRING_TIMEOUT = Whatsapp::Session::PairingPollJob::DEADLINES.fetch('code').to_i

  class << self
    def provider_key
      'native'
    end

    def capabilities
      Whatsapp::Session::Registry.descriptor('native').capabilities
    end

    # `session.logout` unregisters the device with WhatsApp: the store's credentials go
    # with it, and the next connect asks for a new QR.
    def unpairs?
      true
    end

    # The session id is generated when the inbox is saved; the rest of the config is
    # optional toggles, so there is nothing that can be missing here.
    def validate_config(_provider_config)
      []
    end
  end

  # Resolved when they are called, never held in a constant: a constant captured at load
  # time keeps the namespace from before the last reload, and its autoloaded children are
  # gone from it by then.
  def model = Whatsapp::Session::Model
  def commands = Whatsapp::Session::Model::Commands

  def client
    @client ||= Whatsapp::Connector::Client.new(session_id)
  end

  # --- session lifecycle ---------------------------------------------------------

  def connect(command)
    # Nobody owns a session that has never paired, so nobody is reading its command
    # stream and a connect written straight to it would sit there until its deadline.
    # The wake goes on the control stream, which every instance reads, and asks whichever
    # answers to take the session before the connect lands on it.
    client.control(commands::SessionWake.new(desired: 'connected'))
    model::ConnectionState.from_h(client.call(command))
  end

  # The teardown carries no ceiling, and that is the one place where the two readings of
  # `deadline` pull against each other hard enough to matter: a command dropped for
  # arriving late is a device left listed on the customer's phone, while the executor a
  # stuck teardown holds belongs to the session that is going away rather than to an
  # account still in use.
  def disconnect
    client.publish(commands::SessionDisconnect.new)
  end

  def logout
    client.publish(commands::SessionLogout.new)
  end

  # The teardown, published as a pair, and the `logout` is the half that matters most: it
  # unlinks the device from the customer's phone, which is the part of a pairing that
  # outlives this inbox. `session.delete` is what clears the session's own rows, and a
  # connector build without a handler for it answers `unsupported` and undoes nothing -- so
  # sending `delete` alone leaves a device listed on somebody's phone with nothing in
  # Chatwoot corresponding to it.
  #
  # Ordering is what makes the pair safe rather than redundant. Both land on this session's
  # command stream in the order written, so the `delete` that follows finds nothing linked,
  # which is a teardown with less to do and not a failure to retry.
  #
  # Published, not called, for two independent reasons. This runs inside the transaction
  # that destroys the inbox, and an RPC there would hold it open for the round trip. And a
  # teardown is deliberately left pending, with no reply at all, while the session is
  # between owners -- being handed over, or waiting on a lease with room to finish -- so a
  # caller waiting for an answer would time out exactly when the connector is doing the
  # right thing.
  def delete_session
    client.publish(commands::SessionLogout.new)
    client.publish(commands::SessionDelete.new)
  end

  def fetch_connection_state
    model::ConnectionState.from_h(client.call(commands::SessionStatus.new))
  end

  # The code itself arrives as a pairing.code event: WhatsApp takes its time issuing it,
  # and the inbox screen is already listening for connection updates.
  def request_pairing_code(command)
    client.publish(command, timeout: PAIRING_TIMEOUT)
    nil
  end

  # --- messages ------------------------------------------------------------------

  def send_message(command)
    model::SendResult.from_h(
      client.call(command, idempotency_key: "msg:#{command.message_id}", timeout: send_timeout(command))
    )
  end

  # How long to wait for a send, which for a file is not the same question as for a text.
  #
  # Every other RPC answers in milliseconds and the default is right for them. A send with
  # a file has to cover three transfers before the connector can answer, and under the
  # default only a few megabytes fit: past that the send fails on the deadline, is
  # retried, and fails at the same place -- which is why the documented cap was never
  # reachable through this client.
  #
  # Sized from the length the sender already declared rather than from that cap, so a
  # small file is not given the budget meant for the largest one. Never shorter than the
  # default, because every other reason to wait is unchanged.
  def send_timeout(command)
    size = command.content.try(:size).to_i
    return Whatsapp::Connector::Client::RPC_TIMEOUT if size <= 0

    budget = Whatsapp::Connector::Client::RPC_TIMEOUT + (size.to_f / MEDIA_SEND_RATE).ceil
    budget.clamp(Whatsapp::Connector::Client::RPC_TIMEOUT, MEDIA_SEND_MAX_TIMEOUT)
  end

  def edit_message(command)
    model::SendResult.from_h(client.call(command, idempotency_key: "msg:#{command.message_id}"))
  end

  def revoke_message(command)
    client.call(command)
    true
  end

  def react_message(command)
    model::SendResult.from_h(client.call(command, idempotency_key: "msg:#{command.message_id}"))
  end

  def mark_read(command)
    client.publish(command, timeout: DEFERRABLE_TIMEOUT)
  end

  def mark_unread(command)
    client.publish(command, timeout: DEFERRABLE_TIMEOUT)
  end

  # The connector keeps the bytes on its own disk and serves them over its internal HTTP
  # port; the ref that came with the event is a URL there. Those blobs are dropped on a
  # TTL and an LRU quota, so a ref that has lapsed, or one whose blob turns out to be gone
  # already, is asked for again: that makes the connector download it from WhatsApp anew.
  def download_media(command)
    ref = command.ref
    return fetch_blob(refresh(command)) if ref.nil? || !ref.fetchable?

    begin
      fetch_blob(ref)
    rescue Whatsapp::Session::Errors::MediaUnavailable, Whatsapp::Session::Errors::ProviderUnavailable
      # Dropped between the event and this job, which the quota makes ordinary rather than
      # exceptional, or served by an instance that is no longer there: a blob URL names
      # the instance that downloaded it, and that one can be replaced before the job runs.
      # Asking again reaches whoever holds the session now; if that copy is gone as well,
      # it is gone.
      fetch_blob(refresh(command))
    end
  end

  # --- presence and contacts -----------------------------------------------------

  def send_chat_presence(command)
    client.publish(command, timeout: MOMENTARY_TIMEOUT)
  end

  def update_presence(command)
    client.publish(command, timeout: MOMENTARY_TIMEOUT)
  end

  def subscribe_presence(command)
    client.publish(command, timeout: DEFERRABLE_TIMEOUT)
  end

  def check_numbers(command)
    Array(client.call(command)).map { |check| model::NumberCheck.from_h(check) }
  end

  def profile_picture_url(command)
    result = client.call(command)
    result.is_a?(Hash) ? result['url'] : result
  end

  # --- groups --------------------------------------------------------------------

  def create_group(command)
    model::GroupInfo.from_h(client.call(command))
  end

  def group_info(command)
    model::GroupInfo.from_h(client.call(command))
  end

  def list_groups(command)
    Array(client.call(command)).map { |info| model::GroupInfo.from_h(info) }
  end

  def leave_group(command)
    client.call(command)
    true
  end

  # WhatsApp refuses participants one at a time -- a privacy setting, the group's
  # creator, somebody who left recently -- so the answer is a row each and `ok` says only
  # that the command ran. The connector fails the command when nothing was carried out,
  # and this reaches the same verdict from the rows: a caller told `ok` and handed a
  # refusal for every participant it named has had nothing done, which both controllers
  # already turn into the message an operator reads.
  #
  # A partial refusal is not an error. Reporting the participants that were added as not
  # added is a worse answer, and the caller reads the rows to find out which is which.
  def update_group_participants(command)
    rows = Array(client.call(command))
    raise Whatsapp::Session::Errors::GroupParticipantNotAllowed if wholly_refused?(rows)

    rows
  end

  def update_group_name(command)
    client.call(command)
    true
  end

  def update_group_description(command)
    client.call(command)
    true
  end

  def update_group_photo(command)
    client.call(command)
    true
  end

  def update_group_setting(command)
    client.call(command)
    true
  end

  def group_invite_code(command)
    result = client.call(command)
    result.is_a?(Hash) ? result['code'] : result
  end

  def group_join_requests(command)
    Array(client.call(command))
  end

  def handle_group_join_requests(command)
    Array(client.call(command))
  end

  private

  def wholly_refused?(rows)
    rows.present? && rows.all? do |row|
      row.is_a?(Hash) &&
        row.stringify_keys['code'].to_s == Whatsapp::Session::Errors::GroupParticipantNotAllowed::CODE
    end
  end

  def refresh(command)
    model::MediaRef.from_h(client.call(command))
  end

  def session_id
    id = provider_config['session_id']
    raise Whatsapp::Session::Errors::InvalidConfig, 'inbox has no session id' if id.blank?

    id
  end

  # The blob endpoint is authenticated with a token the instances publish in the
  # registry, so an operator has nothing to configure: whoever can read the Redis can
  # read the media.
  def fetch_blob(ref)
    headers = (ref.headers || {}).merge('Authorization' => "Bearer #{client.media_token(ref.url)}")
    file = Down.download(ref.url, headers: headers, max_size: MAX_MEDIA_BYTES)
    model::MediaPayload.new(io: file, mime: ref.mime || file.content_type, filename: file.original_filename, size: file.size)
  rescue Down::NotFound => e
    raise Whatsapp::Session::Errors::MediaUnavailable, "media is gone: #{e.message}"
  rescue Down::ClientError => e
    # A refused request is not a missing file, and the difference decides what the agent
    # sees: media that is gone marks the message unsupported for good, while a connector
    # that will not accept our token is an operational problem the job should retry and
    # then surface as a failed job.
    raise Whatsapp::Session::Errors::Unauthorized, "connector refused the media request: #{e.message}" if refused?(e)

    raise Whatsapp::Session::Errors::MediaUnavailable, "media is gone: #{e.message}"
  rescue Down::TooLarge => e
    raise Whatsapp::Session::Errors::MediaTooLarge, e.message
  rescue Down::Error => e
    raise Whatsapp::Session::Errors::ProviderUnavailable, "media fetch failed: #{e.message}"
  end

  def refused?(error)
    [401, 403].include?(error.response&.code.to_i)
  end
end
