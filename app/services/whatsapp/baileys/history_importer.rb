# Files one chat's history into a Baileys inbox.
#
# A subclass of the webhook service, and that is the whole design. A `messaging-history.set`
# message is a `WAMessage`, byte for byte the shape `messages.upsert` carries, so an
# imported row can be made indistinguishable from a live one by running the code a live one
# runs: the same content extraction, the same fifteen content types, the same rich parsing,
# the same contact resolution. A translator written alongside it would be a second reading
# of the same payload, and the day the two disagree is the day history stops matching what
# the inbox already holds.
#
# What is not reused is the per-message ceremony around that pipeline, and each omission
# has a reason:
#
#   the message lock       the chat is held for the whole batch instead, so a live message
#                          for the same chat cannot open a second conversation beside the
#                          one being filled. The per-message lock lives in the same Redis
#                          namespace, so taking both would be this job waiting on itself.
#   the contact lookup     resolved once per run rather than once per message. Nine hundred
#                          messages is the difference between seconds and minutes.
#   the avatar fetch       skipped. A first pairing would otherwise ask the provider for
#                          five hundred profile pictures at once, which is how an instance
#                          gets rate limited on the day it is set up. A live message fills
#                          it in.
#   the conversation       picked by Inbound::ConversationFinder, which knows about the
#                          archive: a message from last year must not reopen work, and the
#                          reopen policy the live path follows would do exactly that.
#
# Everything the import may set off is suppressed by Whatsapp::Session::SilentWrite for the
# whole run: no notifications, no automations, no outgoing webhooks, no bots, no
# out-of-office replies, no read receipts on the contact's phone. The gap half runs one
# level down, where the dashboard push survives, because somebody is watching the queue it
# lands in.
class Whatsapp::Baileys::HistoryImporter < Whatsapp::IncomingMessageBaileysService
  include Whatsapp::Session::Inbound::HistorySettlement

  # A batch is up to a few hundred messages with a contact resolution behind the first of
  # them. The ordinary thirty seconds is a lease that would expire mid-import, and a lease
  # that expires is not a lock.
  CHAT_LOCK_TTL = 5.minutes

  # All Inbound::Coverage asks of a message is when it was sent. The raw Baileys hash is
  # not a model and never will be, so it is asked through this rather than by teaching
  # Coverage a second shape.
  Occurrence = Struct.new(:sent_at)

  # Threads this run created, which is what tells an artifact from a fact: a new
  # conversation is stamped waiting-since-now and active-now, and for a message from
  # Saturday both readings are wrong.
  attr_reader :opened

  def perform
    @opened = Set.new
    return if batch.empty?

    Whatsapp::Session::Inbound::Locks.with_chat_lock(inbox, lock_ids, ttl: CHAT_LOCK_TTL) do
      pending = unstored(batch.sort_by { |raw| timestamp_of(raw) })
      next if pending.empty?

      runs = pending.group_by { |raw| gap?(raw) }
      Whatsapp::Session::SilentWrite.wrap do
        # Archive first: the two halves land in different threads, and the older one has
        # to exist before the reopen policy is asked which thread is current.
        # An unrequested pile keeps only its gap. The phone offers its whole history at
        # every pairing, and an inbox nobody asked would otherwise fill with a year of
        # somebody's conversations. A first pairing has no coverage at all, so `gap?` calls
        # the whole pile archive and this drops all of it, which is the privacy protection
        # the old outright refusal was standing in for.
        # The archive is silent because a pairing dump is a year of somebody else's
        # conversations arriving at once, and nobody asked to watch that. An answer to a
        # press is the opposite: the operator is looking at the thread it lands in.
        archived = requested ? maybe_announcing { import_run(runs[false], archived: true) } : []
        gap = announcing { import_run(runs[true], archived: false) }
        settle(archived, gap)
      end
    end
  end

  private

  def batch = @batch ||= Array(processed_params[:messages]).select { |raw| writable?(raw) }
  def requested = processed_params[:requested]
  def announce = processed_params[:announce]
  def maybe_announcing(&) = announce ? announcing(&) : yield
  def watermark = processed_params[:watermark]
  def inbound = Whatsapp::Session::Inbound

  # A row that will never become a message: a system marker (`messageStubType`), a revoke
  # or a reaction removal, which mutate a row that has to exist rather than adding one and
  # replayed out of a dump would either no-op or act on a row a later message in the same
  # dump has not written yet, and the markers `ignore_message?` already drops live.
  #
  # Asked here, of the whole batch, rather than at the write: everything between the two
  # -- the contact, its contact_inbox, the conversation -- is resolved once per chat and
  # created before the first row is written, so a chat whose dump holds nothing but markers
  # would leave a contact and an empty resolved conversation behind. Measured on a real
  # pairing: 519 of 614 threads.
  def writable?(raw)
    @raw_message = raw
    return false if raw[:messageStubType].present?

    !(protocol_revoke? || ignore_message? || reaction_removal?)
  end

  # Every id this chat can be addressed by, because WhatsApp names the same peer by phone
  # in one message and by LID in the next, and the live path locks by whichever one its
  # message happened to carry.
  def lock_ids
    @raw_message = batch.first
    return [extract_group_jid] if jid_type == 'group'

    [extract_from_jid(type: 'pn'), extract_from_jid(type: 'lid')]
  end

  # One query for the chat rather than one per message, and inside the lock, so a
  # redelivery cannot pass this check alongside the run writing the rows it checks for.
  # `uniq` first because the phone repeats itself within a single dump.
  def unstored(ordered)
    ordered = ordered.uniq { |raw| raw.dig(:key, :id) }
    ids = ordered.filter_map { |raw| raw.dig(:key, :id) }
    stored = inbox.messages.where(source_id: ids).pluck(:source_id).to_set
    ordered.reject { |raw| stored.include?(raw.dig(:key, :id)) }
  end

  def gap?(raw)
    inbound::Coverage.gap?(Occurrence.new(sent_at_of(raw)), watermark)
  end

  def timestamp_of(raw) = baileys_extract_message_timestamp(raw[:messageTimestamp]).to_i

  def sent_at_of(raw)
    seconds = timestamp_of(raw)
    seconds.positive? ? Time.zone.at(seconds) : nil
  end

  # A run is one chat's messages that all belong on the same side of the boundary, so the
  # contact and the conversation behind them are resolved once for the whole run.
  def import_run(run, archived:)
    return [] if run.blank?

    @raw_message = identifying(run)
    return import_group_run(run, archived) if jid_type == 'group'
    # The same two gates the live path applies: a chat this build has no representation
    # for is not filed, and a 1:1 chat is identified by its LID.
    return [] unless %w[lid user].include?(jid_type)
    return [] if extract_from_jid(type: 'lid').blank?

    set_contact
    return [] if @contact.blank?

    conversation = track(conversation_for(@contact_inbox, run.first, archived))
    run.filter_map { |raw| write(conversation, @contact, raw) }
  end

  # The message that says the most about who the chat belongs to: an incoming one carries
  # phone and LID together, while an echo only carries whatever the chat is addressed by.
  def identifying(run)
    run.find { |raw| !raw.dig(:key, :fromMe) } || run.first
  end

  # A group is the one chat whose author changes from message to message, so its sender is
  # resolved per message while the group contact and its thread are resolved once.
  def import_group_run(run, archived)
    return [] unless Whatsapp::Providers::WhatsappBaileysService.groups_enabled?

    @group_contact_inbox, @group_contact = find_or_create_group_contact
    conversation = track(conversation_for(@group_contact_inbox, run.first, archived))

    run.filter_map do |raw|
      @raw_message = raw
      resolve_group_sender_contact
      add_group_member(@group_contact, @sender_contact) if @sender_contact
      write(conversation, @sender_contact, raw)
    end
  end

  def conversation_for(contact_inbox, raw, archived)
    inbound::ConversationFinder.new(
      inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox,
      archived: archived, occurred_at: sent_at_of(raw)
    ).perform
  end

  def track(conversation)
    opened << conversation.id if conversation.previously_new_record?
    conversation
  end

  # The per-message half of the live pipeline, minus the routing that only makes sense for
  # an arrival. Everything the dump carries that is not a message was dropped by `writable?`
  # before any of this chat's records were resolved.
  def write(conversation, sender, raw)
    @raw_message = raw
    @message = nil

    message = build_and_save_message(conversation: conversation, sender: sender, attach_media: should_attach_media?)
    backdate(message)
  end

  # Dated to when it was sent, not to when it was filed. The thread renders in `created_at`
  # order, so rows written at today's timestamp would stack a year of conversation on top
  # of this morning's. Applied after the insert because `webhook_message_attributes` takes
  # no date, and safe there because SilentWrite has already suppressed the callbacks that
  # would have read the wrong one.
  #
  # A shared-contacts message writes one row per card under a single provider id, so those
  # are moved by id rather than through the one row the builder hands back.
  def backdate(message)
    return if message.blank?

    sent_at = sent_at_of(@raw_message)
    return message if sent_at.blank?

    if message_type == 'contact'
      inbox.messages.where(source_id: raw_message_id).update_all(created_at: sent_at) # rubocop:disable Rails/SkipsModelValidations
      message.reload
    else
      message.update_column(:created_at, sent_at) # rubocop:disable Rails/SkipsModelValidations
    end
    message
  end

  # History carries no media bytes, and the bridge does not fetch them for a dump either,
  # so the file the live path downloads from /media was never written: every media message
  # in an import would be a round trip to a guaranteed 404, three hundred of them on a
  # single chat. Flagged directly instead, which is the row the live path ends up with when
  # a download fails.
  def attach_media_to_message
    @message.is_unsupported = true
  end

  # Says the row was filed after the fact, which is what a report excluding backfilled
  # traffic reads, and what keeps the coverage boundary from moving under its own import.
  def build_message_content_attributes
    super.merge(imported: true)
  end

  # An import must not ask the provider for a profile picture. See the class comment.
  def try_update_contact_avatar(contact = nil); end

  # Raises the flag for the stretch it wraps. Only the gap ever asks for it, and only the
  # dashboard push gets through: see Whatsapp::Session::SilentWrite.
  def announcing(&) = Whatsapp::Session::SilentWrite.wrap(announce: true, &)
end
