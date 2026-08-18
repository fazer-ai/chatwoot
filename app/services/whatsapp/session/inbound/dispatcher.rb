# The single entry point for everything that arrives from a session provider.
#
# The table is explicit on purpose: a type absent from it is ignored, never guessed at
# by name. That is what lets an older Chatwoot keep running against a newer connector,
# and what keeps the Uazapi translator honest about what it can actually produce.
class Whatsapp::Session::Inbound::Dispatcher
  Handlers = Whatsapp::Session::Inbound::Handlers

  HANDLERS = {
    'session.state' => Handlers::ConnectionState,
    'session.logged_out' => Handlers::ConnectionState,
    'session.stream_replaced' => Handlers::ConnectionState,
    'session.temporary_ban' => Handlers::ConnectionState,
    'session.client_outdated' => Handlers::ConnectionState,
    'session.connect_failure' => Handlers::ConnectionState,
    'pairing.qr' => Handlers::ConnectionState,
    'pairing.code' => Handlers::ConnectionState,
    'pairing.success' => Handlers::ConnectionState,
    'pairing.error' => Handlers::ConnectionState,
    'message.received' => Handlers::MessageReceived,
    'message.receipt' => Handlers::MessageReceipt,
    'message.edited' => Handlers::MessageEdited,
    'message.revoked' => Handlers::MessageRevoked,
    'message.reaction' => Handlers::MessageReaction,
    'media.download_failed' => Handlers::MediaDownloadFailed,
    'command.failed' => Handlers::CommandFailed,
    'chat.presence' => Handlers::Presence,
    'presence.update' => Handlers::Presence,
    'contact.picture_changed' => Handlers::ContactPictureChanged,
    'group.joined' => Handlers::GroupJoined,
    'group.updated' => Handlers::GroupUpdated,
    'group.picture_changed' => Handlers::GroupPictureChanged,
    'group.activity' => Handlers::GroupActivity,
    'account.reachout_timelock' => Handlers::AccountLimits,
    'account.new_chat_cap' => Handlers::AccountLimits,
    'raw' => Handlers::Raw
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

    handler.new(channel: channel, event: event).perform
  end

  private

  def skip(reason)
    Rails.logger.debug { "[WHATSAPP SESSION] #{event.type} skipped on inbox #{channel.inbox&.id}: #{reason}" }
    :ignored
  end
end

Whatsapp::Session::Inbound::Dispatcher.prepend_mod_with('Whatsapp::Session::Inbound::Dispatcher')
