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
  # Writes what a send came back with, and answers whether this caller has to revoke the
  # message afterwards.
  #
  # Three writers can fill `source_id` on one send: the send response, the echo of the
  # same message arriving from WhatsApp, and the delete endpoint reading it. Provider
  # revocation is not idempotent, so exactly one of them may enqueue it, and the rule is
  # that it belongs to whoever moves the column from blank to set while the message is
  # deleted. Both halves of that answer are read inside the row lock: deciding before it,
  # or re-reading `deleted` after it, is what lets the delete endpoint slip into the gap
  # and revoke the same message twice.
  #
  # The two lines before the lock are what `Message#update_under_lock!` does for the same
  # reason: `lock!` refuses a record with unsaved changes, and the stale content_attributes
  # hash must never be the thing that gets written back.
  def assign(message, attributes)
    message.restore_attributes(['content_attributes']) if message.content_attributes_changed?
    message.save! if message.changed?

    owns_revoke = false
    message.with_lock do
      assigned_here = message.source_id.blank? && attributes[:source_id].present?
      message.update!(attributes)
      owns_revoke = assigned_here && message.deleted?
    end
    owns_revoke
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
