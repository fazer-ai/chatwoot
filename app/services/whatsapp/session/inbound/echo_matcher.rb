# WhatsApp echoes back every message the session sends, including the ones Chatwoot
# itself dispatched. Those echoes are normally recognized by `source_id`, which is
# written from the send response, but when that response is lost and the job retries,
# the echo carries an id Chatwoot never stored: it would land as a new sender-less
# outgoing message, rendered as if an agent had replied from the phone.
#
# Session sends reserve their WhatsApp id before the request (Outbound::SourceIdReservation),
# so the echo is matched on that reservation instead, and the id the response never
# delivered is filled in here.
class Whatsapp::Session::Inbound::EchoMatcher
  attr_reader :inbox, :contact, :message_id

  def initialize(inbox:, contact:, message_id:)
    @inbox = inbox
    @contact = contact
    @message_id = message_id
  end

  # Returns the already-stored message this echo belongs to, or nil.
  def perform
    return if message_id.blank? || contact.blank?

    reserved = reserved_message
    return if reserved.nil?

    confirm_source_id(reserved) if reserved.source_id.blank?
    reserved
  end

  private

  # Spans every conversation the contact has in this inbox: the sent message can be in
  # any of them, and the answer is the conversation actually holding it.
  def reserved_message
    Message.where(conversation_id: contact.conversations.where(inbox_id: inbox.id).select(:id))
           .where(message_type: :outgoing)
           .where("(content_attributes#>>'{}')::jsonb->>'pending_source_id' = ?", message_id)
           .first
  end

  # The id the send never got to store is what a revoke needs, so a message deleted
  # while that send was in flight can only be taken off the contact's phone once this
  # echo supplies it.
  def confirm_source_id(reserved)
    reserved.update_under_lock!(source_id: message_id)
    ::Messages::DeleteOnChannelJob.perform_later(reserved.id) if reserved.deleted?
  end
end
