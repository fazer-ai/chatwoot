# Asks again whether a number flagged as having no WhatsApp has registered since. Runs when an
# agent opens the conversation and the flag is older than the recheck window: without it a
# stale "no WhatsApp" keeps itself alive, since the warning discourages the send whose
# delivery receipt would clear it.
#
# Messages sent while the number had no account stay undelivered either way: they had no
# device to be encrypted to. Only what is sent from now on reaches the contact.
class Whatsapp::NumberRecheckService
  pattr_initialize [:conversation!]

  def perform
    return unless contact_inbox&.whatsapp_missing_recheck_due?
    return if contact_inbox.contact.phone_number.blank?
    return unless number_check.answerable?

    answer = number_check.lookup(contact_inbox.contact.phone_number)
    # No answer is not a "no": the flag and its date stay as the last real answer left them.
    return if answer.nil?

    answer.exists ? found(answer.phone) : contact_inbox.mark_whatsapp_missing!
    conversation.reload.dispatch_conversation_updated_event
  end

  private

  def contact_inbox
    @contact_inbox ||= conversation.contact_inbox
  end

  def number_check
    @number_check ||= Whatsapp::NumberCheck.new(inbox: contact_inbox.inbox)
  end

  # The same alignment a new conversation gets from ContactInboxBuilder: the contact takes the
  # canonical phone, and the address this thread sends to follows it when it was derived from
  # the old phone. Another contact inbox already holding the canonical address keeps it; this
  # one then stays where it was rather than breaking the unique index.
  def found(canonical_phone)
    if canonical_phone.present?
      old_source_id = contact_inbox.contact.phone_number.delete('+')
      number_check.align_contact(contact_inbox.contact, canonical_phone)
      contact_inbox.reload
      move_source_id(old_source_id, canonical_phone.delete('+'))
    end
    contact_inbox.clear_whatsapp_missing!
  end

  def move_source_id(old_source_id, new_source_id)
    return unless contact_inbox.source_id == old_source_id
    return if contact_inbox.inbox.contact_inboxes.exists?(source_id: new_source_id)

    contact_inbox.update!(source_id: new_source_id)
  end
end
