# The two guards the inbound path needs, in one place.
#
# The `native` backend already delivers a session's events in order on a single
# consumer thread, so nothing there can race. Uazapi arrives as HTTP webhooks fanned
# out over Sidekiq, where two messages of the same chat can land at once, so both
# guards have to hold for the family as a whole.
module Whatsapp::Session::Inbound::Locks
  # Raised when another worker holds the chat: the caller retries the job instead of
  # spinning, so a Sidekiq thread is never parked waiting on Redis.
  class Busy < StandardError; end

  CHAT_LOCK_TTL = 30.seconds
  # Long enough to cover one processing pass, short enough that a marker orphaned by a
  # killed worker heals on its own within the job's retry budget.
  MESSAGE_LOCK_TTL = 30.seconds

  module_function

  # Marks a provider message id as being processed, so a redelivery arriving while the
  # first pass is still running retries instead of racing it into a second row.
  #
  # Holding the marker answers `Busy`, never :duplicate. What makes a *finished* message
  # a duplicate is its stored source_id, and the caller checks that inside; a worker
  # killed between taking the marker and writing the row would otherwise have its own
  # retry answered ":duplicate", which acknowledges the event and loses the message.
  def with_message_lock(inbox, message_id)
    return yield if message_id.blank?

    key = message_key(inbox, message_id)
    token = SecureRandom.uuid
    unless Redis::Alfred.set(key, token, nx: true, ex: MESSAGE_LOCK_TTL)
      raise Busy, "message #{message_id} of inbox #{inbox.id} is already being processed"
    end

    begin
      yield
    ensure
      # By token, for the same reason the chat lock is: a pass that outran the TTL would
      # otherwise delete the marker a redelivery had already taken, and a third delivery
      # could then run alongside it and write a second row.
      Redis::Alfred.delete_if_equals(key, token)
    end
  end

  # Serializes everything that resolves a contact or picks a conversation for one chat,
  # so two messages of the same chat cannot each create their own conversation.
  #
  # Released by token, not by key. `Redis::LockManager#unlock` deletes unconditionally,
  # so an operation that outran the TTL (syncing a large group roster is the realistic
  # one) would delete the lock a second worker had already taken, and from there the two
  # interleave their conversation, membership and activity writes.
  def with_chat_lock(inbox, chat)
    return yield if chat.blank?

    key = chat_key(inbox, chat)
    token = SecureRandom.uuid
    raise Busy, "chat #{chat} of inbox #{inbox.id} is locked" unless Redis::Alfred.set(key, token, nx: true, ex: CHAT_LOCK_TTL)

    begin
      yield
    ensure
      Redis::Alfred.delete_if_equals(key, token)
    end
  end

  def processing?(inbox, message_id)
    Redis::Alfred.get(message_key(inbox, message_id)).present?
  end

  def message_key(inbox, message_id)
    format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: "#{inbox.id}_#{message_id}")
  end

  def chat_key(inbox, chat)
    "WHATSAPP::CONTACT_LOCK::#{inbox.id}_#{chat}"
  end
end
