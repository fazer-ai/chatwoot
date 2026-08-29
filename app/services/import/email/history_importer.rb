# Files one historical email into an email inbox.
#
# A subclass of the live mailbox, and that is the whole design, for the same reason
# Whatsapp::Baileys::HistoryImporter subclasses the webhook service: a message from 2023
# and a message from this morning are the same RFC822 document, so an imported row is made
# indistinguishable from a live one by running the code a live one runs -- the same body
# extraction, the same threading by In-Reply-To and References, the same attachment
# handling, the same contact resolution. A parallel reader written alongside it would be a
# second interpretation of the same bytes, and the day the two disagree is the day the
# archive stops matching what the inbox already holds.
#
# What it changes, and why each one has to change:
#
#   the date          `create_message` stamps `created_at` at insert time, so a mailbox
#                     replayed today would stack four years of conversation on top of this
#                     afternoon. Applied after the insert because the attribute builder
#                     takes no date, and safe there because SilentWrite has already
#                     suppressed the callbacks that would have read the wrong one.
#   the thread        born resolved and dated to its first message, never resolved
#                     afterwards. `notify_status_change` and `create_activity` are
#                     after_update callbacks, so a thread born in this state fires no
#                     resolution event and writes no "resolved by" line into itself;
#                     transitioning to the same state would do both and file every
#                     imported thread into today's figures.
#   the contact name  the live path reads the display name off `Reply-To` when there is
#                     one. A web form that sends as the company and points `Reply-To` at
#                     the customer therefore names every contact after the form. The
#                     address still has to come from `Reply-To` -- that is the customer --
#                     so only the name falls back to `From`.
#   the attachments   optional, and off for anything older than the caller's cutoff. The
#                     attachments on a mailbox this size outweigh its bodies by fifty to
#                     one, against a provider that allows 2.5 GB a day, so fetching all of
#                     them is a months-long job. Skipped ones stay reachable: the row keeps its
#                     Message-ID, which is what `rfc822msgid:` searches by.
#
# Everything the write may set off is suppressed by Import::SilentWrite for the whole run:
# no dashboard push, no automations, no outgoing webhooks, no bots, no notifications, no
# auto-replies to a message that was answered in 2023. Unlike the on-demand WhatsApp
# import there is nobody watching a screen, so this never announces.
class Import::Email::HistoryImporter < Imap::ImapMailbox
  include Import::HistorySettlement

  attr_reader :opened, :outcome, :outcome_kind

  def initialize(attachments: nil)
    @attachments = Import::Email::AttachmentPolicy.build(attachments)
    @opened = Set.new
    @created = Set.new
    super()
  end

  # Returns the message it wrote, or nil when the pipeline declined the mail (an invalid
  # sender, a duplicate Message-ID, a notification of our own).
  #
  # `text_only` is the caller saying it fetched a lean copy and left this message's
  # attachments in the mailbox, which is recorded on the row. See Import::TEXT_ONLY_SQL.
  def import(mail, channel, text_only: false)
    @occurred_at = occurred_at(mail)
    @text_only = text_only
    @outcome = nil
    existing = stored(mail, channel)
    return enrich(mail, channel, existing) if existing

    # One transaction around the write and the settlement, because the dedupe key is the
    # row: a run that commits the message and then stops leaves stamps describing the
    # import, and the next pass skips that Message-ID in `unstored` and never comes back to
    # it. Together they either both land or neither does, and neither leaves a row the
    # resume cannot see.
    Import::SilentWrite.wrap do
      ActiveRecord::Base.transaction do
        process(mail, channel)
        settle_thread
      end
    end
    @outcome_kind = @outcome ? :importadas : :recusadas
    @outcome
  end

  private

  # Asked of the inbox, not of the conversation. The live pipeline dedupes inside the
  # thread it just picked, which is right for an arrival and wrong for a replay: a mail
  # whose References no longer resolve opens a fresh conversation, and the check then runs
  # against a thread that is empty by construction and passes. Measured on 29 real
  # messages, a second pass duplicated 25 of them.
  def stored(mail, channel)
    id = sanitize_mailbox_value(mail.message_id)
    return if id.blank?

    channel.inbox.messages.find_by(source_id: id)
  end

  # The attachments a narrower pass left behind, fetched onto the row that is already
  # filed.
  #
  # Without this the archive cannot be widened. A first pass under `ATTACHMENTS=none`
  # files every message text-only; a second pass under a cutoff finds the Message-ID
  # already stored, calls it done, and the attachments stay in a mailbox nobody will read
  # again -- silently, and with no setting that recovers them, since resetting the cursor
  # only re-walks UIDs the stored check will refuse a second time.
  #
  # It runs the same `add_attachments_to_message` over the same `MailPresenter` the live
  # path runs, which is the whole reason this class subclasses the mailbox: an attachment
  # filed here is the one the pipeline would have filed. Nothing else about the message is
  # touched -- it already has its body, its date, its thread and its contact.
  def enrich(mail, channel, message)
    @outcome_kind = :inalteradas
    return if skip_attachments? || !incomplete?(message)

    @inbound_mail = mail
    @channel = channel
    load_account
    load_inbox
    decorate_mail
    @message = message
    @conversation = message.conversation
    Import::SilentWrite.wrap { fill_attachments }
    @outcome_kind = :enriquecidas
    @outcome = @message
  end

  # The flag is cleared in the same transaction that writes the attachments, so a run that
  # dies between them leaves the row still asking to be enriched rather than claiming to be
  # complete while holding nothing.
  def fill_attachments
    ActiveRecord::Base.transaction do
      add_attachments_to_message
      @message.update!(content_attributes: @message.content_attributes.except('imported_text_only'))
    end
  end

  def incomplete?(message)
    ActiveModel::Type::Boolean.new.cast(message.content_attributes['imported_text_only']) == true
  end

  # Shared with the backfill, which reads it off the header alone to decide the attachment
  # cutoff. Falling back to now would be the bug this class exists to fix.
  def occurred_at(mail) = Import::Email::Timestamp.of(mail)

  # Resolved unconditionally, dated when there is a date. The two are separate decisions
  # and only one of them depends on the clock: a thread out of the archive is not somebody's
  # open work whatever its headers say, and leaving it open because its `Date` was
  # unreadable would put it in the queue as live traffic -- which is the one outcome the
  # whole import is built to avoid.
  def find_or_create_conversation
    super
    return if @conversation.blank?

    if @conversation.previously_new_record?
      @opened << @conversation.id
      @created << @conversation.id
      stamps = { status: :resolved }
      stamps[:created_at] = @occurred_at if @occurred_at
      @conversation.update_columns(stamps) # rubocop:disable Rails/SkipsModelValidations
    else
      backdate_conversation
    end
    @conversation
  end

  # A thread opens on the first of its messages this run happens to see, and IMAP hands
  # them out in arrival order rather than in the order they were written -- so the message
  # that opens a conversation is routinely not its oldest, and the thread ends up dated
  # after mail it contains. Only ever moved earlier, and only on a thread with no live
  # traffic in it: on one somebody is working, the creation date is real.
  #
  # `@created` rather than `@opened`, which the settlement empties as it goes. The query is
  # the resume path only, and reached only when there is actually a date to correct.
  def backdate_conversation
    return if @occurred_at.blank? || @conversation.created_at <= @occurred_at
    return unless @created.include?(@conversation.id) || imported_only?(@conversation)

    @conversation.update_columns(created_at: @occurred_at) # rubocop:disable Rails/SkipsModelValidations
  end

  def imported_only?(conversation)
    conversation.messages.where.not(Import::IMPORTED_SQL).none?
  end

  # Address from `Reply-To`, name from `From`. See the class comment.
  def identify_contact_name
    return super unless redirected_reply_to?

    sanitize_mailbox_value(from_display_name.presence || super)
  end

  # A `Reply-To` that points somewhere other than `From`: the mail was sent on the
  # customer's behalf, so `From` holds who it is about and `Reply-To` holds where to write.
  def redirected_reply_to?
    reply_to = address_of(@inbound_mail[:reply_to])
    from = address_of(@inbound_mail[:from])
    reply_to.present? && from.present? && reply_to != from
  end

  def from_display_name = address(@inbound_mail[:from])&.name
  def address_of(field) = address(field)&.address

  # `MailPresenter` keeps its own parser private, and the mailbox never needed one because
  # the live path only ever reads the presenter's `sender_name`. Same shape, same rescue:
  # a malformed From is a header this run declines to read, not a message it drops.
  def address(field)
    return if field.nil?

    Mail::Address.new(field.value)
  rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError, NoMethodError
    nil
  end

  # Says the row was filed after the fact. Read by Inbound::Coverage and HistorySettlement,
  # and by any report that means to exclude backfilled traffic. See Import::IMPORTED_SQL.
  def sanitized_content_attributes
    attributes = super.merge(imported: true)
    return attributes unless @text_only

    attributes.merge(imported_text_only: true)
  end

  def create_message
    super
    return if @message.blank?

    @message.update_column(:created_at, @occurred_at) if @occurred_at # rubocop:disable Rails/SkipsModelValidations
    @outcome = @message
  end

  # An attachment older than the cutoff is not fetched at all, rather than fetched and
  # dropped: the cost this avoids is the provider's daily byte budget, and that is spent at
  # the fetch. The caller does not hand us the parts in that case, so there is nothing to
  # attach and the message keeps its text.
  def add_attachments_to_message
    return if skip_attachments?

    super
  end

  def skip_attachments? = @attachments.skip?(@occurred_at)

  # `HistorySettlement` works a batch at a time because a WhatsApp dump arrives that way.
  # A mailbox arrives one message at a time, so the batch here is the single row just
  # written -- correct, and idempotent across the run: every stamp it sets only ever moves
  # in the direction the newest row justifies.
  # Settled row by row, and the conversation leaves `opened` as soon as it has been: that
  # set says "these stamps are the import's own artifacts, take the batch outright", which
  # is true exactly once. IMAP hands out UIDs in arrival order and a thread is filed in the
  # order its messages were sent, so the two disagree routinely -- and while a conversation
  # stays in the set, a later UID carrying an older date bypasses the monotonic guard and
  # drags `last_activity_at` backwards, one row at a time, for the whole run.
  def settle_thread
    return if @outcome.blank? || @conversation.blank?

    settle(settleable, [])
    @opened.delete(@conversation.id)
  end

  # A resolved thread runs no waiting clock, so the row just written is the whole story and
  # the batch is that row. An open one is somebody's live queue, and there `first_unanswered`
  # has to see the replies already stored after this message: settled on the new row alone it
  # reads an answered conversation as pending and moves `waiting_since` back to a date in the
  # archive, which files a thread somebody already handled into the unattended and SLA
  # reports. Only that path pays for the extra read, and only that path needs it.
  def settleable
    return [@outcome] if @conversation.resolved?

    @conversation.messages.to_a
  end

  # Nothing about a bulk backfill is worth pushing to a screen. The level exists for the
  # on-demand WhatsApp case; here it stays silent, so the hook the settlement calls
  # through resolves to a plain yield.
  def announcing(&) = yield
end
