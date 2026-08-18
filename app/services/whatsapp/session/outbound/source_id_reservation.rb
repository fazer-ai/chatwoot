# The WhatsApp id a send will use, chosen here instead of by the provider.
#
# `source_id` can only be written from the send response, so a send whose response never
# arrives (socket drop, read timeout, worker restart) leaves nothing to recognize the
# echo of our own message by: it lands as a fresh "sent from the phone" message.
# Reserving the id up front closes that window, and a retry reuses it so WhatsApp still
# sees a single message.
#
# The shape mirrors what WhatsApp clients generate: the "3EB0" prefix and 18 uppercase
# hex characters.
module Whatsapp::Session::Outbound::SourceIdReservation
  PREFIX = '3EB0'.freeze

  module_function

  def generate
    "#{PREFIX}#{SecureRandom.hex(9).upcase}"
  end

  # Read-or-generate runs under the row lock, which re-reads the row: a reaction toggle
  # in the meantime clears the reservation precisely to force a fresh id, and sending
  # under a stale one would resend the previous reaction with an unmatchable echo.
  #
  # Written with update_columns: the reservation is bookkeeping for a send that has not
  # happened yet, so it must not fire message.updated (cable, webhooks, agent bots,
  # search reindex) nor bump updated_at.
  # Whoever moves `source_id` from blank to set owns the revoke of a message deleted
  # mid-send, and the send response, the echo and the delete endpoint all race for it.
  # A conditional UPDATE decides that in one statement: exactly one caller sees a row
  # affected, no matter how the three interleave. Returns whether this caller was it.
  def claim_source_id(message, source_id)
    return false if source_id.blank?

    Message.where(id: message.id, source_id: nil).update_all(source_id: source_id).positive? # rubocop:disable Rails/SkipsModelValidations
  end

  def reserve(message)
    message.with_lock do
      next message.pending_source_id if message.pending_source_id.present?

      message.pending_source_id = generate
      message.update_columns(content_attributes: message.content_attributes) # rubocop:disable Rails/SkipsModelValidations
      message.pending_source_id
    end
  end
end
