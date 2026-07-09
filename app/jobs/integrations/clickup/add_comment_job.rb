# Posts a comment on a ClickUp task on behalf of the AurisChat operator who
# hit "Adicionar informação" on the ticket detail modal. Prefixes with the
# operator's name so the ops team sees who wrote what — the ClickUp comment
# author will be the API key owner (Auris | Admin), not the operator.
class Integrations::Clickup::AddCommentJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 3
  BACKOFF = [1.minute, 5.minutes, 30.minutes].freeze

  def perform(ticket_id, text, author_user_id = nil, attempt = 0)
    ticket = Ticket.find_by(id: ticket_id)
    return if ticket.nil? || text.blank?
    return unless ticket.sync_synced?

    Integrations::Clickup::Client.new.add_comment(
      ticket.clickup_task_id,
      format_comment(text, author_user_id)
    )
  rescue Integrations::Clickup::Client::Unauthorized => e
    Rails.logger.error("[ClickUp] add_comment auth failure ticket=#{ticket_id}: #{e.message}")
  rescue Integrations::Clickup::Client::Error, StandardError => e
    Rails.logger.warn("[ClickUp] add_comment retry ticket=#{ticket_id} attempt=#{attempt} err=#{e.message}")
    return if attempt + 1 >= MAX_ATTEMPTS

    wait = BACKOFF[attempt] || BACKOFF.last
    self.class.set(wait: wait).perform_later(ticket_id, text, author_user_id, attempt + 1)
  end

  private

  def format_comment(text, author_user_id)
    author = author_user_id.present? ? User.find_by(id: author_user_id) : nil
    return text.to_s if author.blank?

    "#{author.name} (#{author.email}):\n#{text}"
  end
end
