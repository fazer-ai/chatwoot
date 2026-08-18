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
  MESSAGE_LOCK_TTL = 1.day

  module_function

  # Marks a provider message id as being processed. A redelivery of the same id while
  # the first pass is still running answers :duplicate instead of writing a second row.
  # The marker is released at the end: what makes a *finished* message a duplicate is
  # its stored source_id, not this key.
  def with_message_lock(inbox, message_id)
    return yield if message_id.blank?

    key = message_key(inbox, message_id)
    return :duplicate unless Redis::Alfred.set(key, true, nx: true, ex: MESSAGE_LOCK_TTL)

    begin
      yield
    ensure
      Redis::Alfred.delete(key)
    end
  end

  # Serializes everything that resolves a contact or picks a conversation for one chat,
  # so two messages of the same chat cannot each create their own conversation.
  def with_chat_lock(inbox, chat)
    return yield if chat.blank?

    key = chat_key(inbox, chat)
    lock_manager = Redis::LockManager.new
    raise Busy, "chat #{chat} of inbox #{inbox.id} is locked" unless lock_manager.lock(key, CHAT_LOCK_TTL)

    begin
      yield
    ensure
      lock_manager.unlock(key)
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
