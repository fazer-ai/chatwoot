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
# So every receipt this app sends leaves a marker on the conversation, and the inbound
# handlers skip the *timestamp* for a conversation carrying one. Only the timestamp: the
# message's own status still transitions, because a message we acknowledged really is read.
module Whatsapp::SelfReadReceipts
  # Per conversation, not per message, because that is the grain of the thing being
  # asserted: this app acknowledged *this chat*, and one receipt covers a batch. It is also
  # the only key the read side can match on. A receipt is addressed by provider message id,
  # and a shared-contact payload stores several rows under one `source_id`, so the handler
  # resolves one echo to several messages; a per-row marker would cover whichever row the
  # sender happened to name and let its siblings clear the badge anyway.
  #
  # Held far longer than the echo takes to arrive (seconds), because the failure is
  # asymmetric. The inbound path defers and retries on its own ladder --
  # `wait: :polynomially_longer, attempts: 6` is roughly a quarter of an hour before the
  # last try -- and a queue backlog stacks on top of that, so a marker sized to the echo
  # would be gone by the time the echo is finally handled, which is the bug. Held too long
  # it only swallows a genuine read from the paired phone, and the handler's own note says
  # why that is cheap: the next receipt on the chat carries the same marker forward.
  TTL = 30.minutes

  module_function

  # Before the send rather than after: uazapi can have the webhook in flight by the time its
  # HTTP response lands here, and a marker left behind by a send that then failed costs
  # nothing but a window in which this app declines to move a marker it never meant to move.
  def record(conversation)
    Redis::Alfred.setex(key(conversation), '1', TTL)
  end

  def echo?(conversation)
    Redis::Alfred.exists?(key(conversation))
  end

  def key(conversation)
    format(Redis::Alfred::WHATSAPP_SELF_READ_RECEIPT, conversation_id: conversation.id)
  end
end
