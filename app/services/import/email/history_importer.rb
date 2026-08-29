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

  attr_reader :opened, :outcome

  # `attachments_since` is nil to take every attachment, or a Time to take only those on
  # messages newer than it.
  def initialize(attachments_since: nil)
    @attachments_since = attachments_since
    @opened = Set.new
    super()
  end

  # Returns the message it wrote, or nil when the pipeline declined the mail (an invalid
  # sender, a duplicate Message-ID, a notification of our own).
  def import(mail, channel)
    return if stored?(mail, channel)

    @occurred_at = mail.date&.to_time
    @outcome = nil
    Import::SilentWrite.wrap do
      process(mail, channel)
      settle_thread
    end
    @outcome
  end

  private

  # Asked of the inbox, not of the conversation. The live pipeline dedupes inside the
  # thread it just picked, which is right for an arrival and wrong for a replay: a mail
  # whose References no longer resolve opens a fresh conversation, and the check then runs
  # against a thread that is empty by construction and passes. Measured on 29 real
  # messages, a second pass duplicated 25 of them.
  def stored?(mail, channel)
    id = sanitize_mailbox_value(mail.message_id)
    return false if id.blank?

    channel.inbox.messages.exists?(source_id: id)
  end

  # The two dates a conversation is asked for. `occurred_at` is when the mail was sent;
  # falling back to now would be the bug this class exists to fix, so a mail without a
  # parseable Date is filed at the epoch of its own thread instead of at today.
  def find_or_create_conversation
    super
    return if @conversation.blank?

    if @conversation.previously_new_record?
      @opened << @conversation.id
      @conversation.update_columns(created_at: @occurred_at, status: :resolved) if @occurred_at # rubocop:disable Rails/SkipsModelValidations
    end
    @conversation
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
    super.merge(imported: true)
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

  def skip_attachments?
    return false if @attachments_since.blank?
    return false if @occurred_at.blank?

    @occurred_at < @attachments_since
  end

  # `HistorySettlement` works a batch at a time because a WhatsApp dump arrives that way.
  # A mailbox arrives one message at a time, so the batch here is the single row just
  # written -- correct, and idempotent across the run: every stamp it sets only ever moves
  # in the direction the newest row justifies.
  def settle_thread
    return if @outcome.blank? || @conversation.blank?

    settle([@outcome], [])
  end

  # Nothing about a bulk backfill is worth pushing to a screen. The level exists for the
  # on-demand WhatsApp case; here it stays silent, so the hook the settlement calls
  # through resolves to a plain yield.
  def announcing(&) = yield
end
