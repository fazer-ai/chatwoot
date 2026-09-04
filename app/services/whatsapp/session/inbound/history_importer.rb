# Files a batch of history into the inbox.
#
# What arrives is one undifferentiated pile: the phone answers a request with everything
# it has for a chat, and answers the first connection with everything it has, full stop.
# One live instance answered a request for fifty messages with nine hundred and forty
# seven. So the policy on volume, on status and on what may be set off is applied here, on
# the way in, and never assumed of the provider.
#
# Two decisions run through it, and they are not the same decision:
#
#   what it is       Inbound::Coverage splits the pile against the last moment the inbox
#                    was known to be receiving. Newer means nobody has had the chance to
#                    read it: that is late mail and it belongs in the queue. Older is
#                    history and it belongs in the archive, filed resolved.
#   what it may do   almost nothing. Import::SilentWrite holds for the whole
#                    run, so no imported message notifies, automates, posts a webhook,
#                    wakes a bot or answers with a template, whichever half it lands in.
#                    The one exception follows the same split: the gap half is written
#                    announcing, so the queue an operator is watching updates itself,
#                    while the archive stays silent because a reader has nothing to gain
#                    from eight hundred backdated rows arriving one cable frame at a time.
class Whatsapp::Session::Inbound::HistoryImporter
  include Import::HistorySettlement

  attr_reader :channel, :messages

  # Threads this run created, which is what tells an artifact from a fact. A new
  # conversation is stamped by its own callbacks as waiting since now and active now, and
  # for a message from Saturday both readings are wrong; on a thread that already existed
  # the same two columns hold something real that the import may only refine.
  attr_reader :opened

  # Whether anybody asked for this pile. False is the phone volunteering what it has,
  # which happens at every pairing, and then only the gap is filed: see `import_chat`.
  attr_reader :requested

  def initialize(channel:, messages:, requested: true)
    @channel = channel
    @messages = messages
    @requested = requested
    @opened = Set.new
  end

  def perform
    batches = importable.group_by { |message| message.chat.to_jid }
    return :ignored if batches.empty?

    # Read once, before anything is written. Every message in the run is classified
    # against the same boundary, or the first imported message would move the line the
    # rest of its own batch is measured against.
    watermark = inbound::Coverage.watermark(inbox)
    Import::SilentWrite.wrap do
      batches.each_value { |batch| import_chat(batch, watermark) }
    end
    :handled
  end

  private

  def inbox = channel.inbox
  def inbound = Whatsapp::Session::Inbound

  def importable
    messages.select { |message| importable?(message) }
  end

  # The same gate the live path applies, for the same reasons: a chat Chatwoot has no
  # representation for is not filed, and a group is only filed when the inbox handles
  # groups. A history dump is where an inbox without the capability would otherwise
  # discover several years of group traffic at once.
  def importable?(message)
    return false if message.id.blank? || message.chat.blank? || message.chat.ignorable?
    return channel.session_capabilities.include?('groups') if message.group?

    true
  end

  # Oldest first, which is what makes the thread read in the order it happened and what
  # lets `settle` take the last row as the state the conversation ended in. Archive before
  # gap for the same reason: the two land in different threads, and the older one has to
  # exist first or the reopen policy picks it up as the current conversation.
  def import_chat(batch, watermark)
    ordered = batch.sort_by { |message| message.timestamp.to_i }

    lock_ids = inbound::ChatIdentity.lock_ids(ordered.first)
    inbound::Locks.with_chat_lock(inbox, lock_ids, ttl: inbound::Locks::IMPORT_CHAT_LOCK_TTL, defer_to_waiters: true) do
      pending = unstored(ordered)
      next if pending.empty?

      runs = pending.group_by { |message| inbound::Coverage.gap?(message, watermark) }
      # An unrequested pile keeps only its gap. The phone offers its whole history at every
      # pairing, and an inbox nobody asked would otherwise fill with a year of somebody's
      # conversations; what arrived while the session was down is a different thing, and it
      # is the only part of that offer this inbox is missing. A first pairing has no
      # coverage at all, so `gap?` calls the whole pile archive and this drops all of it,
      # which is what the old outright refusal was protecting.
      archived = requested ? import_run(runs[false], archived: true) : []
      gap = announcing { import_run(runs[true], archived: false) }
      settle(archived, gap)
    end
  end

  # Inside the lock, so a redelivery cannot pass this check alongside the run that is
  # writing the rows it is checking for. One query for the chat rather than one per
  # message: a batch is up to two hundred of them.
  #
  # `uniq` before the query, because the phone repeats itself: forty six of the nine
  # hundred and forty seven messages one instance sent were second copies of an id already
  # in the same dump. They happened to fall in different batches there, where the stored
  # row catches them, but nothing promises that.
  def unstored(ordered)
    ordered = ordered.uniq(&:id)
    stored = inbox.messages.where(source_id: ordered.map(&:id)).pluck(:source_id).to_set
    ordered.reject { |message| stored.include?(message.id) }
  end

  # A run is one chat's messages that all belong on the same side of the boundary, so the
  # contact and the conversation behind them are resolved once rather than once per
  # message. On nine hundred messages that is the difference between an import that takes
  # seconds and one that takes minutes.
  def import_run(run, archived:)
    return [] if run.blank?
    return run.filter_map { |message| import_group(message, archived) } if run.first.group?

    contact_inbox = resolve_contact(identifying(run))
    return [] if contact_inbox.nil?

    conversation = track(conversation_for(contact_inbox, run.first, archived))
    run.filter_map { |message| write(conversation, contact_inbox.contact, message) }
  end

  # The message in the run that says the most about who the chat belongs to: an incoming
  # one carries phone and LID together, while an echo only carries whatever the chat is
  # addressed by, which can be a LID with no number behind it.
  def identifying(run)
    run.find(&:incoming?) || run.first
  end

  def conversation_for(contact_inbox, message, archived)
    inbound::ConversationFinder.new(
      inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox,
      archived: archived, occurred_at: message.sent_at
    ).perform
  end

  # A group is the one chat whose author changes from message to message, so its sender
  # is resolved per message. Its own contact and thread are looked up each time too, which
  # is a query a group batch pays and a 1:1 batch does not.
  def import_group(message, archived)
    resolver = inbound::GroupResolver.new(inbox: inbox, group: message.chat, sender: message.sender)
    group = resolver.perform
    conversation = track(resolver.conversation_for(group.group_contact_inbox, archived: archived, occurred_at: message.sent_at))

    write(conversation, group.sender_contact, message)
  end

  # `overwrite: false` because the push name on a message from last June is what the
  # contact was called last June, and the live path has been keeping it current since.
  # Avatars are skipped for the same kind of reason and one more: an inbox connecting for
  # the first time would otherwise ask the provider for five hundred profile pictures in
  # one go, which is how an instance gets itself rate limited on the day it is set up. A
  # live message fills the avatar in.
  def resolve_contact(message)
    inbound::ContactResolver.new(
      inbox: inbox, party: inbound::ChatIdentity.peer_party(message), overwrite: false, skip_avatar: true
    ).perform
  end

  def track(conversation)
    opened << conversation.id if conversation.previously_new_record?
    conversation
  end

  def write(conversation, sender, message)
    inbound::MessageWriter.new(conversation: conversation, inbound: message, sender: sender, imported: true).perform
  end

  # What the suppressed callbacks would have kept up to date, applied once per
  # conversation instead of once per message, and only in the direction that is true.
  # Raises the flag for the stretch it wraps. Only the gap ever asks for it, and only the
  # dashboard push gets through: see Import::SilentWrite.
  def announcing(&) = Import::SilentWrite.wrap(announce: true, &)
end
