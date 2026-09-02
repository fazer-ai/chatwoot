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
# So every receipt this app sends leaves a short-lived marker, and the inbound handlers skip
# the *timestamp* for messages carrying one. Only the timestamp: the message's own status
# still transitions, because a message we acknowledged really is read.
module Whatsapp::SelfReadReceipts
  # Long enough for the provider to echo, which takes seconds. Short enough that a genuine
  # read from the paired phone is barely ever swallowed -- and swallowing one is mild, since
  # it names messages this app has already acknowledged on the operator's behalf.
  TTL = 2.minutes

  module_function

  # Before the send rather than after: uazapi can have the webhook in flight by the time its
  # HTTP response lands here, and a marker left behind by a send that then failed costs
  # nothing but two minutes of not moving a marker this app did not intend to move anyway.
  def record(messages)
    Array(messages).each { |message| Redis::Alfred.setex(key(message), '1', TTL) }
  end

  def echo?(message)
    Redis::Alfred.exists?(key(message))
  end

  def key(message)
    format(Redis::Alfred::WHATSAPP_SELF_READ_RECEIPT, message_id: message.id)
  end
end
