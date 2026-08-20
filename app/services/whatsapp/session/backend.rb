# The contract every session backend implements. Callers never branch on the provider:
# they build a canonical command, hand it to the backend and get a canonical result.
#
# Every method here raises NotSupported. A backend implements exactly the methods its
# declared capabilities cover, and the shared examples assert both directions: a declared
# capability must have a working method, and an undeclared one must keep raising.
class Whatsapp::Session::Backend
  attr_reader :channel

  def initialize(channel)
    @channel = channel
  end

  class << self
    # Provider key stored in channel_whatsapp.provider.
    def provider_key
      raise NotImplementedError
    end

    def capabilities
      [].freeze
    end

    def supports?(capability)
      capabilities.include?(capability.to_s)
    end

    # Whether this backend's connection state has to be pulled. A backend that pushes
    # every transition answers false and is never polled; one whose provider pushes only
    # some of them answers true. Uazapi's webhook, for one, does not carry the QR as it
    # rotates nor the account limits, so its inboxes would sit on a stale QR forever.
    def state_polling?
      false
    end

    # Whether `logout` ends the pairing or only the connection. A provider that cannot
    # unpair keeps the account's credentials whatever it is asked, so connecting again
    # resumes the very session that was just refused: what that decides is whether
    # re-pairing is a way out of a wrong-number quarantine, which for most of this layer
    # is the only exit an operator has.
    def unpairs?
      false
    end

    # Whether this inbox's provider runs outside the deployment's network. What it decides
    # is the address outbound media is offered at: a service on the far side of the
    # firewall fetches the attachment over the internet and can never resolve
    # INTERNAL_HOST_URL, while one sitting next to Rails on a closed installation can
    # resolve nothing else.
    #
    # Asked per inbox rather than per provider, because a provider that is normally a
    # hosted service can also be self-hosted, and then it is a neighbour.
    def hosted?(_channel)
      false
    end

    # What identifies the instance an inbox is pointed at, in a form safe to carry in a job
    # payload and compare later: a webhook is authenticated when it arrives and dispatched
    # afterwards, and a poll asks the provider before it writes, so both have a gap in the
    # middle for the inbox to be re-pointed. nil where the provider has no such notion.
    def instance_fingerprint(_channel)
      nil
    end

    # The webhook translator for a provider that pushes over HTTP. nil means there is
    # nothing to translate: the connector publishes canonical events already.
    def translator
      nil
    end

    # Schema-only validation: returns the list of invalid/missing config keys. Must not
    # touch the network, so saving an inbox never depends on a provider being up.
    def validate_config(_provider_config)
      []
    end
  end

  # --- session lifecycle -----------------------------------------------------------
  def connect(_command) = not_supported!(:connect)
  def disconnect = not_supported!(:disconnect)
  def logout = not_supported!(:logout)
  def delete_session = not_supported!(:delete_session)
  def fetch_connection_state = not_supported!(:fetch_connection_state)
  def request_pairing_code(_command) = not_supported!(:request_pairing_code)
  def import_session(_payload) = not_supported!(:import_session)

  # Whatever the provider holds pointing at this inbox, released on its own. Called when
  # the inbox is destroyed, after the session teardown and whether or not that teardown
  # worked: destruction goes ahead either way, and a registration left behind is a
  # customer's instance posting at a channel that no longer exists for as long as it keeps
  # trying. Best effort by definition, and a no-op for a backend that registers nothing.
  def release_registration = nil

  # The other half: whatever the provider has to hold to reach this inbox, put back in
  # place. Called when the address it should post to changes without the session itself
  # changing, and a no-op for a backend that registers nothing.
  def ensure_registration = nil

  # Reach-out lock and new-chat quota, polled while the session is open.
  def fetch_account_limits = not_supported!(:fetch_account_limits)

  # --- messaging -------------------------------------------------------------------
  def send_message(_command) = not_supported!(:send_message)
  def edit_message(_command) = not_supported!(:edit_message)
  def revoke_message(_command) = not_supported!(:revoke_message)
  def react_message(_command) = not_supported!(:react_message)
  def mark_read(_command) = not_supported!(:mark_read)
  def mark_unread(_command) = not_supported!(:mark_unread)
  # Takes the whole MessageDownloadMedia command, not a bare ref: the contract requires
  # the message id, which is what lets a provider find the original message and fetch its
  # bytes again once the ref it first handed out has lapsed.
  def download_media(_command) = not_supported!(:download_media)

  # --- presence --------------------------------------------------------------------
  def send_chat_presence(_command) = not_supported!(:send_chat_presence)
  def update_presence(_command) = not_supported!(:update_presence)
  def subscribe_presence(_command) = not_supported!(:subscribe_presence)

  # --- contacts --------------------------------------------------------------------
  def check_numbers(_command) = not_supported!(:check_numbers)
  def profile_picture_url(_command) = not_supported!(:profile_picture_url)

  # --- groups ----------------------------------------------------------------------
  def create_group(_command) = not_supported!(:create_group)
  def group_info(_command) = not_supported!(:group_info)
  def list_groups(_command) = not_supported!(:list_groups)
  def leave_group(_command) = not_supported!(:leave_group)
  def update_group_participants(_command) = not_supported!(:update_group_participants)
  def update_group_name(_command) = not_supported!(:update_group_name)
  def update_group_description(_command) = not_supported!(:update_group_description)
  def update_group_photo(_command) = not_supported!(:update_group_photo)
  def update_group_setting(_command) = not_supported!(:update_group_setting)
  # Returns the invite code alone, never the chat.whatsapp.com link: the dashboard
  # endpoint builds the URL from it, so a backend handing back a full link produces one
  # with the host in it twice.
  def group_invite_code(_command) = not_supported!(:group_invite_code)
  def group_join_requests(_command) = not_supported!(:group_join_requests)
  def handle_group_join_requests(_command) = not_supported!(:handle_group_join_requests)

  def capabilities
    self.class.capabilities
  end

  def supports?(capability)
    self.class.supports?(capability)
  end

  private

  def provider_config
    channel.provider_config || {}
  end

  def not_supported!(method_name)
    raise Whatsapp::Session::Errors::NotSupported,
          "#{self.class.name} does not implement #{method_name}"
  end
end
