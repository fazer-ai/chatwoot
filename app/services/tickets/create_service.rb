# Creates a Feedback ticket for an AI/agent message and enqueues the
# asynchronous ClickUp sync. Called by the /api/v1/tickets controller
# (frontend) and by rspec / rails console (backend smoke tests).
#
# Everything remote-side is deferred to a job:
# - `Integrations::Clickup::CreateTaskJob` — writes the ClickUp task and
#   backfills the id / url / status.
# - `Integrations::Clickup::AddCommentJob` (PR2, invoked on comment).
# - `Integrations::Clickup::AttachFileJob` (PR2, invoked per attachment).
#
# This service does not talk to ClickUp itself so the response is not gated
# on the ClickUp API being reachable — the ticket persists locally as
# `pending_sync`, the job retries with backoff, and the operator sees the
# ticket immediately in Meus Tickets regardless.
class Tickets::CreateService
  def initialize(user:, message:, params:)
    @user = user
    @message = message
    @account = message.account
    @conversation = message.conversation
    @params = params.to_h.with_indifferent_access
  end

  def perform
    ticket = build_ticket
    Integrations::Clickup::CreateTaskJob.perform_later(ticket.id)
    ticket
  end

  private

  def build_ticket
    @account.tickets.create!(
      user: @user,
      context: @message,
      conversation: @conversation,
      relatar_problema: @params[:relatar_problema].to_s.strip,
      comportamento_esperado: @params[:comportamento_esperado].to_s.strip,
      sync_status: :pending_sync
    )
  end
end
