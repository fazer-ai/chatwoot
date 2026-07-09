# Syncs a Ticket to ClickUp by creating the task and stamping the returned
# task id / url / status back on the local Ticket. Retries transient
# failures with exponential backoff, gives up hard on auth errors, and
# stops retrying after MAX_ATTEMPTS.
class Integrations::Clickup::CreateTaskJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 3
  # Backoff schedule in seconds, indexed by attempt count *before* the
  # current try. First failure waits 5min, second 15min, then 1h.
  BACKOFF_SECONDS = [5 * 60, 15 * 60, 60 * 60].freeze

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    return if ticket.nil? || ticket.sync_synced?

    client = Integrations::Clickup::Client.new
    return mark_failed(ticket, 'CLICKUP_API_KEY is not configured') unless client.configured?

    apply_clickup_response(ticket, create_clickup_task(client, ticket))
  rescue Integrations::Clickup::Client::Unauthorized => e
    # No point retrying — the key needs to be fixed by the admin.
    mark_failed(ticket, e.message)
  rescue Integrations::Clickup::Client::Error, StandardError => e
    register_failure(ticket, e)
  end

  private

  def create_clickup_task(client, ticket)
    client.create_task(
      list_id: Integrations::Clickup::FieldMap::FEEDBACK_LIST_ID,
      name: build_task_name(ticket),
      description: ticket.relatar_problema,
      custom_fields: build_custom_fields(ticket)
    )
  end

  def apply_clickup_response(ticket, response)
    clickup_task_id = response['id']
    raise Client::ProviderUnavailable, 'ClickUp did not return a task id' if clickup_task_id.blank?

    ticket.update!(
      clickup_task_id: clickup_task_id,
      clickup_task_url: response['url'],
      clickup_status_id: response.dig('status', 'id'),
      clickup_status_name: response.dig('status', 'status'),
      sync_status: :synced,
      sync_attempts: ticket.sync_attempts + 1,
      sync_error: nil
    )
  end

  def register_failure(ticket, error)
    ticket.update!(sync_attempts: ticket.sync_attempts + 1, sync_error: error.message)

    if ticket.sync_attempts >= MAX_ATTEMPTS
      mark_failed(ticket, error.message)
      Rails.logger.error(
        "[ClickUp] ticket #{ticket.id} sync_failed after #{ticket.sync_attempts} attempts: #{error.message}"
      )
    else
      wait = BACKOFF_SECONDS[ticket.sync_attempts - 1] || BACKOFF_SECONDS.last
      self.class.set(wait: wait.seconds).perform_later(ticket.id)
    end
  end

  def mark_failed(ticket, message)
    ticket.update!(sync_status: :sync_failed, sync_error: message)
  end

  def build_task_name(ticket)
    agent = ticket.user&.name.presence || 'Sistema'
    "Feedback — Conversa ##{ticket.conversation&.display_id} — #{agent}"
  end

  def build_custom_fields(ticket)
    fields = base_custom_fields(ticket)

    if ticket.comportamento_esperado.present?
      fields << { id: Integrations::Clickup::FieldMap::FIELDS[:comportamento_esperado],
                  value: ticket.comportamento_esperado }
    end

    canal_option = Integrations::Clickup::FieldMap.canal_option_for(ticket.conversation&.inbox)
    fields << { id: Integrations::Clickup::FieldMap::FIELDS[:canal], value: canal_option } if canal_option.present?

    fields
  end

  def base_custom_fields(ticket)
    [
      { id: Integrations::Clickup::FieldMap::FIELDS[:ambiente], value: Integrations::Clickup::FieldMap.ambiente_option_for(frontend_url) },
      { id: Integrations::Clickup::FieldMap::FIELDS[:contexto], value: Integrations::Clickup::FieldMap::CONTEXTO_OPTIONS[:mensagem] },
      { id: Integrations::Clickup::FieldMap::FIELDS[:chat_id], value: ticket.conversation&.display_id },
      { id: Integrations::Clickup::FieldMap::FIELDS[:account_id], value: ticket.account_id },
      { id: Integrations::Clickup::FieldMap::FIELDS[:aurischat_url], value: build_aurischat_url(ticket) },
      { id: Integrations::Clickup::FieldMap::FIELDS[:relatar_problema], value: ticket.relatar_problema.to_s },
      { id: Integrations::Clickup::FieldMap::FIELDS[:user_id], value: ticket.user_id.to_s },
      { id: Integrations::Clickup::FieldMap::FIELDS[:user_name], value: ticket.user&.name.to_s }
    ]
  end

  def build_aurischat_url(ticket)
    base = frontend_url.presence || 'http://localhost:3000'
    base = base.chomp('/')
    conv = ticket.conversation&.display_id
    "#{base}/app/accounts/#{ticket.account_id}/conversations/#{conv}?messageId=#{ticket.context_id}"
  end

  def frontend_url
    ENV.fetch('FRONTEND_URL', '')
  end
end
