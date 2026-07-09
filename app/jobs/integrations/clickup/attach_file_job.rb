# Uploads a single ActiveStorage blob to a ClickUp task as an attachment.
# Called by Api::V1::Accounts::TicketsController#create for every file the
# operator drops into the feedback form. Runs after `CreateTaskJob` synced
# the ticket — we require the `clickup_task_id` and simply reschedule with
# backoff when the ticket has not been synced yet, so the operator does not
# have to sequence "upload after task is created" from the frontend.
class Integrations::Clickup::AttachFileJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 5
  WAIT_FOR_SYNC = 30.seconds
  FAILURE_BACKOFF = [2.minutes, 10.minutes, 30.minutes, 2.hours, 6.hours].freeze

  def perform(ticket_id, blob_signed_id, attempt = 0)
    ticket = Ticket.find_by(id: ticket_id)
    return if ticket.nil?
    return reschedule(ticket_id, blob_signed_id, attempt, WAIT_FOR_SYNC) if ticket.sync_pending_sync?
    return log_orphan(ticket, blob_signed_id) if ticket.sync_sync_failed?

    upload_blob(ticket, blob_signed_id)
  rescue Integrations::Clickup::Client::Unauthorized
    log_orphan(ticket, blob_signed_id)
  rescue Integrations::Clickup::Client::Error, StandardError => e
    handle_transient_failure(ticket, ticket_id, blob_signed_id, attempt, e)
  end

  private

  def upload_blob(ticket, blob_signed_id)
    blob = ActiveStorage::Blob.find_signed(blob_signed_id)
    return if blob.nil?

    blob.open do |io|
      Integrations::Clickup::Client.new.upload_attachment(
        ticket.clickup_task_id,
        io: io,
        filename: blob.filename.to_s
      )
    end

    # Local storage was temporary — ClickUp is the canonical version now.
    blob.purge_later
  end

  def handle_transient_failure(ticket, ticket_id, blob_signed_id, attempt, error)
    Rails.logger.warn("[ClickUp] attach retry ticket=#{ticket_id} attempt=#{attempt} err=#{error.message}")
    return log_orphan(ticket, blob_signed_id) if attempt + 1 >= MAX_ATTEMPTS

    wait = FAILURE_BACKOFF[attempt] || FAILURE_BACKOFF.last
    reschedule(ticket_id, blob_signed_id, attempt + 1, wait)
  end

  def reschedule(ticket_id, blob_signed_id, attempt, wait)
    self.class.set(wait: wait).perform_later(ticket_id, blob_signed_id, attempt)
  end

  # A local blob that never made it to ClickUp is dead weight — the operator
  # cannot resend from the UI and manually re-uploading is out of scope for
  # Phase 1. Log so we notice and drop the file.
  def log_orphan(ticket, blob_signed_id)
    Rails.logger.error(
      "[ClickUp] orphan attachment ticket=#{ticket&.id} blob=#{blob_signed_id} — task never synced"
    )
    blob = ActiveStorage::Blob.find_signed(blob_signed_id)
    blob&.purge_later
  end
end
