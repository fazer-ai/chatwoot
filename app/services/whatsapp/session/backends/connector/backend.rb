# The `native` provider: a session held by the Go connector, reached over Redis.
#
# Every method here is the same shape: build a canonical command, hand it to the client,
# and turn the reply into the canonical object the caller expects. What is fire and
# forget on the wire is fire and forget here too, and its failures come back later as a
# command.failed event rather than as a return value.
class Whatsapp::Session::Backends::Connector::Backend < Whatsapp::Session::Backend
  Model = Whatsapp::Session::Model
  Commands = Whatsapp::Session::Model::Commands

  # A cap on what a single media download may pull into the Rails process. WhatsApp
  # itself stops well below this; the limit is there so a wrong URL cannot fill a disk.
  MAX_MEDIA_BYTES = 100.megabytes

  class << self
    def provider_key
      'native'
    end

    def capabilities
      Whatsapp::Session::Registry.descriptor('native').capabilities
    end

    # The session id is generated when the inbox is saved; the rest of the config is
    # optional toggles, so there is nothing that can be missing here.
    def validate_config(_provider_config)
      []
    end
  end

  def client
    @client ||= Whatsapp::Connector::Client.new(session_id)
  end

  # --- session lifecycle ---------------------------------------------------------

  def connect(command)
    # Nobody owns a session that has never paired, so nobody is reading its command
    # stream and a connect written straight to it would sit there until its deadline.
    # The wake goes on the control stream, which every instance reads, and asks whichever
    # answers to take the session before the connect lands on it.
    client.control(Commands::SessionWake.new(desired: 'connected'))
    Model::ConnectionState.from_h(client.call(command))
  end

  def disconnect
    client.publish(Commands::SessionDisconnect.new)
  end

  def logout
    client.publish(Commands::SessionLogout.new)
  end

  def delete_session
    client.publish(Commands::SessionDelete.new)
  end

  def fetch_connection_state
    Model::ConnectionState.from_h(client.call(Commands::SessionStatus.new))
  end

  # The code itself arrives as a pairing.code event: WhatsApp takes its time issuing it,
  # and the inbox screen is already listening for connection updates.
  def request_pairing_code(command)
    client.publish(command)
    nil
  end

  # The limits ride along with the session status, which is the only thing that knows
  # them: they are pushed as events the rest of the time.
  def fetch_account_limits
    status = client.call(Commands::SessionStatus.new) || {}
    status.slice('reachout_time_lock', 'new_chat_cap')
  end

  # --- messages ------------------------------------------------------------------

  def send_message(command)
    Model::SendResult.from_h(client.call(command, idempotency_key: "msg:#{command.message_id}"))
  end

  def edit_message(command)
    Model::SendResult.from_h(client.call(command, idempotency_key: "msg:#{command.message_id}"))
  end

  def revoke_message(command)
    client.call(command)
    true
  end

  def react_message(command)
    Model::SendResult.from_h(client.call(command, idempotency_key: "msg:#{command.message_id}"))
  end

  def mark_read(command)
    client.publish(command)
  end

  def mark_unread(command)
    client.publish(command)
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
    client.publish(command)
  end

  def update_presence(command)
    client.publish(command)
  end

  def subscribe_presence(command)
    client.publish(command)
  end

  def check_numbers(command)
    Array(client.call(command)).map { |check| Model::NumberCheck.from_h(check) }
  end

  def profile_picture_url(command)
    result = client.call(command)
    result.is_a?(Hash) ? result['url'] : result
  end

  # --- groups --------------------------------------------------------------------

  def create_group(command)
    Model::GroupInfo.from_h(client.call(command))
  end

  def group_info(command)
    Model::GroupInfo.from_h(client.call(command))
  end

  def list_groups(command)
    Array(client.call(command)).map { |info| Model::GroupInfo.from_h(info) }
  end

  def leave_group(command)
    client.call(command)
    true
  end

  def update_group_participants(command)
    Array(client.call(command))
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

  def refresh(command)
    Model::MediaRef.from_h(client.call(command))
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
    Model::MediaPayload.new(io: file, mime: ref.mime || file.content_type, filename: file.original_filename, size: file.size)
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
