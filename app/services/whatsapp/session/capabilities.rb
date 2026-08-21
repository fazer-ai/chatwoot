# What a backend can actually do. Declared statically per backend and surfaced to the
# frontend on the inbox payload, replacing both the `respond_to?` duck typing on
# Channel::Whatsapp and the provider-name literals scattered across the dashboard.
module Whatsapp::Session::Capabilities
  ALL = %w[
    qr_pairing
    code_pairing
    session_import
    echo_by_reserved_id
    edit
    revoke
    reactions
    typing
    presence
    presence_subscribe
    read_receipts
    mark_unread
    check_number
    profile_picture
    groups
    group_admin
    group_invites
    group_join_requests
    account_limits
    history_sync
    calls
    media_download
  ].freeze

  # Capability -> the Backend method it unlocks. Only capabilities that map to a single
  # entry point are listed: `qr_pairing` is covered by `connect` (every backend has it),
  # and `echo_by_reserved_id`, `history_sync` and `calls` describe behavior rather than a
  # call. The shared examples use this map to assert that a declared capability is
  # actually implemented, and that an undeclared one still raises NotSupported.
  METHODS = {
    'code_pairing' => :request_pairing_code,
    'session_import' => :import_session,
    'edit' => :edit_message,
    'revoke' => :revoke_message,
    'reactions' => :react_message,
    'typing' => :send_chat_presence,
    'presence' => :update_presence,
    'presence_subscribe' => :subscribe_presence,
    'read_receipts' => :mark_read,
    'mark_unread' => :mark_unread,
    'check_number' => :check_numbers,
    'profile_picture' => :profile_picture_url,
    'account_limits' => :fetch_account_limits,
    'media_download' => :download_media,
    'groups' => :group_info,
    'group_admin' => :update_group_participants,
    'group_invites' => :group_invite_code,
    'group_join_requests' => :group_join_requests
  }.freeze

  GROUP_CAPABILITIES = %w[groups group_admin group_invites group_join_requests].freeze

  def self.validate!(capabilities)
    unknown = capabilities.map(&:to_s) - ALL
    raise ArgumentError, "unknown whatsapp session capabilities: #{unknown.join(', ')}" if unknown.any?

    capabilities.map(&:to_s).freeze
  end
end
