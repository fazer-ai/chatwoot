# The single entry point for everything that arrives from a session provider.
#
# The table is explicit on purpose: a type absent from it is ignored, never guessed at
# by name. That is what lets an older Chatwoot keep running against a newer connector,
# and what keeps the Uazapi translator honest about what it can actually produce.
class Whatsapp::Session::Inbound::Dispatcher
  # Handler names, not handler classes. A class object stored here is captured from
  # another file, and a reload leaves this table pointing at the previous generation,
  # whose own namespace aliases are stale in turn. Resolving the name when the event
  # arrives costs nothing and cannot go out of date.
  HANDLERS = {
    'session.state' => 'ConnectionState',
    'session.logged_out' => 'ConnectionState',
    'session.stream_replaced' => 'ConnectionState',
    'session.temporary_ban' => 'ConnectionState',
    'session.client_outdated' => 'ConnectionState',
    'session.connect_failure' => 'ConnectionState',
    'pairing.qr' => 'ConnectionState',
    'pairing.code' => 'ConnectionState',
    'pairing.success' => 'ConnectionState',
    'pairing.error' => 'ConnectionState',
    'message.received' => 'MessageReceived',
    'message.receipt' => 'MessageReceipt',
    'message.edited' => 'MessageEdited',
    'message.revoked' => 'MessageRevoked',
    'message.reaction' => 'MessageReaction',
    'media.download_failed' => 'MediaDownloadFailed',
    'command.failed' => 'CommandFailed',
    'chat.presence' => 'Presence',
    'presence.update' => 'Presence',
    'contact.picture_changed' => 'ContactPictureChanged',
    'group.joined' => 'GroupJoined',
    'group.updated' => 'GroupUpdated',
    'group.picture_changed' => 'GroupPictureChanged',
    'group.activity' => 'GroupActivity',
    'account.reachout_timelock' => 'AccountLimits',
    'account.new_chat_cap' => 'AccountLimits',
    'raw' => 'Raw'
  }.freeze

  # Types the catalog defines and this layer deliberately drops. Listed so that a type
  # missing from both tables shows up as a gap instead of as silence.
  IGNORED = %w[
    pairing.passkey_request pairing.passkey_confirmation contact.identity_changed
    call.offer call.terminate history.sync
  ].freeze

  attr_reader :channel, :event

  # Returns :handled, :ignored or :duplicate. Raises Locks::Busy when another worker
  # holds the chat, which the caller answers by retrying the job.
  def self.dispatch(channel, event)
    new(channel, event).perform
  end

  def initialize(channel, event)
    @channel = channel
    @event = event
  end

  def perform
    return skip('unknown payload') unless event.known?

    handler = HANDLERS[event.type]
    return skip('no handler') if handler.nil?
    return skip('inbox disowned its session') unless allowed_while_disowned?(handler)

    "Whatsapp::Session::Inbound::Handlers::#{handler}".constantize.new(channel: channel, event: event).perform
  end

  private

  # A session paired with a number this inbox is not configured for is somebody else's
  # WhatsApp account, and its chats must not be filed here. The logout that removes it is
  # asynchronous and can be retried for a while, so this is what keeps the wrong account's
  # messages out in the meantime. Connection events still run, because they are how the
  # inbox reports the problem and how a correct pairing clears it.
  def allowed_while_disowned?(handler)
    return true if handler == 'ConnectionState'

    channel.provider_connection['error_code'] != 'wrong_phone_number'
  end

  def skip(reason)
    Rails.logger.debug { "[WHATSAPP SESSION] #{event.type} skipped on inbox #{channel.inbox&.id}: #{reason}" }
    :ignored
  end
end

Whatsapp::Session::Inbound::Dispatcher.prepend_mod_with('Whatsapp::Session::Inbound::Dispatcher')
