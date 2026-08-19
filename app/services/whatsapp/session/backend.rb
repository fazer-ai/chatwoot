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

  # Reach-out lock and new-chat quota, polled while the session is open.
  def fetch_account_limits = not_supported!(:fetch_account_limits)

  # --- messaging -------------------------------------------------------------------
  def send_message(_command) = not_supported!(:send_message)
  def edit_message(_command) = not_supported!(:edit_message)
  def revoke_message(_command) = not_supported!(:revoke_message)
  def react_message(_command) = not_supported!(:react_message)
  def mark_read(_command) = not_supported!(:mark_read)
  def mark_unread(_command) = not_supported!(:mark_unread)
  def download_media(_ref) = not_supported!(:download_media)

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
