# Mail the IMAP fetch picks up from the inbox's own address is the business replying from
# the mailbox itself (the Gmail web UI of the same address), not the customer writing again.
# Upstream stores every fetched mail as incoming from the conversation's contact, so the
# human's reply showed under the customer's name, counted as customer traffic in reports,
# and had an AI agent on the inbox answer on top of the human (#861).
#
# Prepended rather than edited in place: `Imap::ImapMailbox`, `MailboxHelper` and
# `MailboxSanitizer` are upstream files, and every line changed there conflicts on each sync.
module ImapOwnAddressReply
  def process(mail, channel)
    return super unless channel.email.casecmp?(MailPresenter.new(mail, channel.account).original_sender.to_s)

    @inbound_mail = mail
    @channel = channel
    @own_address_reply = true
    load_account
    load_inbox
    decorate_mail
    return unless incoming_email_from_valid_email?

    ActiveRecord::Base.transaction do
      next if duplicate_email?

      # Threaded by its headers only. The contact fallbacks upstream uses would make the
      # inbox its own customer, which is what opened conversations with the inbox address.
      @conversation = conversation_by_in_reply_to || find_conversation_by_reference_ids
      if @conversation.nil?
        Rails.logger.info("[IMAP] Skipping mail from the inbox's own address that threads into no conversation: " \
                          "inbox #{@inbox.id} message_id #{@processed_mail.message_id}")
        next
      end

      create_message
      add_attachments_to_message
    end
  end

  private

  def conversation_by_in_reply_to
    return if in_reply_to.blank?

    message = @inbox.messages.find_by(source_id: in_reply_to)
    message.conversation if message.present? && !message.forwarded?
  end

  # Outgoing with no sender: nobody sent it through Chatwoot. The source id it keeps is what
  # dedups the next fetch and what tells the send path the mail already left, so it is never
  # sent to the customer a second time.
  def sanitized_message_attributes(source_id)
    return super unless @own_address_reply

    super.merge(message_type: 'outgoing', sender: nil)
  end
end

Rails.application.config.to_prepare do
  Imap::ImapMailbox.prepend(ImapOwnAddressReply)
end
