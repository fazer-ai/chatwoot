# A read receipt this app sends comes back as an inbound one. Uazapi answers our own
# `/message/markread` with a `read` webhook naming the very messages we just acknowledged
# (see the `RECEIPTS` note in its webhook translator), and both inbound handlers read that
# as "a device of this account opened the chat" and move `agent_last_seen_at`.
#
# That is harmless while the only sender is an agent opening the thread: the controller has
# already written the same marker, and the handlers only ever move it forward. It is not
# harmless for an agent bot's receipt, which is provider-only by design -- the echo would
# clear the unread badge for a conversation no human has read, and `bot_handoff!` does not
# rewind it, so the thread would reach the human queue already looking read.
#
# So every receipt this app sends records the provider ids it acknowledged, and the inbound
# handlers skip the *timestamp* for a message whose id is on that list. Only the timestamp:
# the message's own status still transitions, because a message we acknowledged really is
# read.
module Whatsapp::SelfReadReceipts
  # Keyed by the provider message id, which is the identity a receipt is addressed by, and
  # neither of the two things next to it. Not the row: one `source_id` can resolve to
  # several rows (a shared-contact payload stores a card each) and the handler applies the
  # receipt to all of them, so a per-row marker covers whichever row the sender named and
  # lets its siblings clear the badge. Not the conversation: that suppresses a genuine read
  # from the paired phone for every *other* message in the chat, and since each receipt
  # refreshes the key, a busy bot thread would never let a device read through again.
  #
  # The ids live in one set per conversation so the cost is a round trip per receipt rather
  # than per message: an assignee opening a long backlog acknowledges the whole thing in one
  # call, on the worker the event dispatcher shares.
  #
  # Held far longer than the echo takes to arrive (seconds), because the failure is
  # asymmetric. The inbound path defers and retries on its own ladder --
  # `wait: :polynomially_longer, attempts: 6` is roughly a quarter of an hour before the
  # last try -- and a queue backlog stacks on top of that, so a marker sized to the echo
  # would be gone by the time the echo is finally handled, which is the bug. Held too long
  # it only declines to re-read messages this app has already acknowledged.
  TTL = 30.minutes

  module_function

  # Before the send rather than after: uazapi can have the webhook in flight by the time its
  # HTTP response lands here, and a marker left behind by a send that then failed costs
  # nothing but a window in which this app declines to move a marker it never meant to move.
  def record(conversation, messages)
    ids = source_ids(messages)
    return if ids.empty?

    Redis::Alfred.with do |conn|
      conn.sadd(key(conversation), ids)
      conn.expire(key(conversation), TTL.to_i)
    end
  end

  # The whole set, not a membership test per message. A receipt is a batch by nature and a
  # large one by habit -- opening a chat produced one read event naming 246 messages -- and
  # the session handler resolves all of them in a single query for exactly that reason; a
  # test per message would put 246 sequential Redis round trips back on the queue inbound
  # messages share. The payload is short ids, bounded by what this app acknowledged inside
  # the TTL window.
  def acknowledged(conversation)
    Set.new(Redis::Alfred.with { |conn| conn.smembers(key(conversation)) })
  end

  def key(conversation)
    format(Redis::Alfred::WHATSAPP_SELF_READ_RECEIPT, conversation_id: conversation.id)
  end

  # `pluck` on a relation so a backlog is one column of strings rather than a row each; the
  # providers materialize what they need on their own terms.
  def source_ids(messages)
    ids = messages.respond_to?(:pluck) && messages.is_a?(ActiveRecord::Relation) ? messages.pluck(:source_id) : messages.map(&:source_id)
    ids.compact_blank
  end
end
