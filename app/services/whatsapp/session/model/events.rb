# Canonical inbound event payloads, one class per wire type. The connector produces them
# directly; the Uazapi translator produces the same objects from its webhook. Handlers
# are written against these and never see a provider payload.
module Whatsapp::Session::Model::Events
  Address = Whatsapp::Session::Model::Address
  Party = Whatsapp::Session::Model::Party
  Content = Whatsapp::Session::Model::Content
  GroupInfo = Whatsapp::Session::Model::GroupInfo
  InboundMessage = Whatsapp::Session::Model::InboundMessage
  Serializable = Whatsapp::Session::Model::Serializable
  WireError = Whatsapp::Session::Model::WireError

  class SessionState < Data.define(:state, :reason, :phone, :lid, :quarantine, :ban)
    include Serializable
    wire_type 'session.state'
  end

  class SessionLoggedOut < Data.define(:reason, :on_connect)
    include Serializable
    wire_type 'session.logged_out'
    defaults on_connect: false
  end

  class SessionStreamReplaced < Data.define(:reason)
    include Serializable
    wire_type 'session.stream_replaced'
  end

  class SessionTemporaryBan < Data.define(:ban)
    include Serializable
    wire_type 'session.temporary_ban'
  end

  class SessionClientOutdated < Data.define(:version)
    include Serializable
    wire_type 'session.client_outdated'
  end

  class SessionConnectFailure < Data.define(:reason, :code)
    include Serializable
    wire_type 'session.connect_failure'
  end

  class PairingQr < Data.define(:png_data_url, :expires_in_ms)
    include Serializable
    wire_type 'pairing.qr'
  end

  class PairingCode < Data.define(:code, :phone)
    include Serializable
    wire_type 'pairing.code'
  end

  class PairingSuccess < Data.define(:phone, :lid, :platform)
    include Serializable
    wire_type 'pairing.success'
  end

  class PairingError < Data.define(:reason, :message)
    include Serializable
    wire_type 'pairing.error'
  end

  class PairingPasskeyRequest < Data.define(:request_id, :public_key)
    include Serializable
    wire_type 'pairing.passkey_request'
  end

  class PairingPasskeyConfirmation < Data.define(:request_id, :code)
    include Serializable
    wire_type 'pairing.passkey_confirmation'
  end

  # What the session missed while it was down, counted by the server before it replays
  # any of it, so a reader can say how much is coming instead of watching a queue move.
  # The messages themselves arrive afterwards as ordinary `message.received`.
  class SessionOfflineSyncPreview < Data.define(:messages, :receipts, :notifications, :app_data_changes, :total)
    include Serializable
    wire_type 'session.offline_sync_preview'
  end

  # The replay is over: what has not arrived by now is not coming.
  class SessionOfflineSyncCompleted < Data.define(:count)
    include Serializable
    wire_type 'session.offline_sync_completed'
  end

  class MessageReceived < Data.define(:message)
    include Serializable
    wire_type 'message.received'
    coerce message: InboundMessage
  end

  class MessageReceipt < Data.define(:chat, :message_ids, :type, :participant, :error, :timestamp)
    include Serializable
    wire_type 'message.receipt'
    coerce chat: Address, participant: Address, error: WireError

    TYPES = %w[delivered read played failed].freeze
  end

  class MessageEdited < Data.define(:chat, :sender, :message_id, :from_me, :content, :timestamp)
    include Serializable
    wire_type 'message.edited'
    coerce chat: Address, sender: Party, content: Content
    defaults from_me: false
  end

  class MessageRevoked < Data.define(:chat, :sender, :message_id, :by, :timestamp)
    include Serializable
    wire_type 'message.revoked'
    coerce chat: Address, sender: Party

    def by_self?
      by == 'self'
    end
  end

  class MessageReaction < Data.define(:id, :chat, :sender, :from_me, :target_id, :emoji, :timestamp)
    include Serializable
    wire_type 'message.reaction'
    coerce chat: Address, sender: Party
    defaults from_me: false

    def removal?
      emoji.blank?
    end
  end

  class MediaDownloadFailed < Data.define(:chat, :message_id, :reason, :recoverable)
    include Serializable
    wire_type 'media.download_failed'
    coerce chat: Address
    # Whether the file may still be somewhere the provider can reach: WhatsApp drops a
    # file off its CDN long before the sender's phone forgets it, and asking for it again
    # is what recovers a message that sat in a backlog. Everything else here is the file
    # being gone.
    #
    # False is what a provider that predates the field says by saying nothing, and it is
    # the half that changes nothing: the bubble is flagged and nobody comes back for the
    # bytes, which is what this event has always meant.
    defaults recoverable: false
  end

  class CommandFailed < Data.define(:command_id, :command_type, :message_id, :error)
    include Serializable
    wire_type 'command.failed'
    coerce error: WireError
  end

  class ChatPresence < Data.define(:chat, :sender, :state)
    include Serializable
    wire_type 'chat.presence'
    coerce chat: Address, sender: Party

    STATES = %w[composing recording paused].freeze
  end

  class PresenceUpdate < Data.define(:party, :state, :last_seen)
    include Serializable
    wire_type 'presence.update'
    coerce party: Party
  end

  class ContactPictureChanged < Data.define(:party, :removed)
    include Serializable
    wire_type 'contact.picture_changed'
    coerce party: Party
    defaults removed: false
  end

  class ContactIdentityChanged < Data.define(:party, :timestamp)
    include Serializable
    wire_type 'contact.identity_changed'
    coerce party: Party
  end

  class GroupJoined < Data.define(:info)
    include Serializable
    wire_type 'group.joined'
    coerce info: GroupInfo
  end

  class GroupUpdated < Data.define(:group, :actor, :timestamp, :changes)
    include Serializable
    wire_type 'group.updated'

    class Changes < Data.define(:subject, :description, :announce, :locked, :join_approval, :member_add_mode,
                                :join, :leave, :promote, :demote)
      include Serializable
      coerce join: [Party], leave: [Party], promote: [Party], demote: [Party]

      # A `Data` instance is never blank, so a payload whose changes are all nil, or that
      # carries nothing but a member a newer connector added, would otherwise read as a
      # real change and open a group for a no-op event.
      def any?
        # `nil` is "not reported", which is the only thing that means no change. An empty
        # string is a description or a subject the group removed, and `false` is a
        # setting turned off: both are changes, and `present?` would read them as none.
        to_h.values.any? { |value| value.is_a?(Array) ? value.present? : !value.nil? }
      end

      def participant_changes?
        [join, leave, promote, demote].any?(&:present?)
      end
    end

    coerce group: Address, actor: Party, changes: Changes
  end

  class GroupPictureChanged < Data.define(:group, :actor, :removed)
    include Serializable
    wire_type 'group.picture_changed'
    coerce group: Address, actor: Party
    defaults removed: false
  end

  class GroupActivity < Data.define(:groups)
    include Serializable
    wire_type 'group.activity'
    coerce groups: [Address]
  end

  class AccountReachoutTimelock < Data.define(:reachout_time_lock)
    include Serializable
    wire_type 'account.reachout_timelock'
  end

  class AccountNewChatCap < Data.define(:new_chat_cap)
    include Serializable
    wire_type 'account.new_chat_cap'
  end

  class CallOffer < Data.define(:call_id, :from, :video, :timestamp)
    include Serializable
    wire_type 'call.offer'
    coerce from: Party
    defaults video: false
  end

  class CallTerminate < Data.define(:call_id, :from, :reason)
    include Serializable
    wire_type 'call.terminate'
    coerce from: Party
  end

  class HistorySync < Data.define(:kind, :progress, :data)
    include Serializable
    wire_type 'history.sync'
  end

  class Raw < Data.define(:provider_event, :data)
    include Serializable
    wire_type 'raw'
  end

  # A type this version does not know about. The contract is additive, so an older
  # Chatwoot talking to a newer connector must ignore what it cannot read instead of
  # failing the whole shard.
  class Unknown < Data.define(:type, :payload)
    include Serializable
    wire_type 'unknown'
  end

  CLASSES = [
    SessionState, SessionLoggedOut, SessionStreamReplaced, SessionTemporaryBan, SessionClientOutdated,
    SessionConnectFailure, SessionOfflineSyncPreview, SessionOfflineSyncCompleted,
    PairingQr, PairingCode, PairingSuccess, PairingError, PairingPasskeyRequest,
    PairingPasskeyConfirmation, MessageReceived, MessageReceipt, MessageEdited, MessageRevoked, MessageReaction,
    MediaDownloadFailed, CommandFailed, ChatPresence, PresenceUpdate, ContactPictureChanged, ContactIdentityChanged,
    GroupJoined, GroupUpdated, GroupPictureChanged, GroupActivity, AccountReachoutTimelock, AccountNewChatCap,
    CallOffer, CallTerminate, HistorySync, Raw
  ].freeze

  BY_TYPE = CLASSES.index_by(&:wire_type).freeze
  TYPES = BY_TYPE.keys.freeze

  def self.build(type, payload)
    klass = BY_TYPE[type]
    return Unknown.new(type: type, payload: payload) if klass.nil?

    klass.from_h(payload || {})
  end
end
