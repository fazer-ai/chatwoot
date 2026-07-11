# Applies a ClickUp webhook event to the local Ticket.
#
# Two events are relevant:
# - `taskStatusUpdated`: mirror ClickUp's status onto the Ticket. This is
#   the source of truth for the badge the operator sees in Meus Tickets.
# - `taskCustomFieldUpdated`: when the ops team fills the "Resposta para o
#   Cliente" field, copy the new value onto the Ticket so it renders in
#   the ticket detail modal.
#
# Other events (assignee, priority, comment) are ignored — Phase 1 only
# surfaces status + response back to the operator.
#
# After a change lands the service also broadcasts `ticket.updated` on
# ActionCable so Meus Tickets refreshes live and, when the status
# transitions into `FieldMap::NOTIFIABLE_STATUS_SLUGS` (resolvido / restrição
# / encerrado), the frontend fires a toast + bumps the sidebar unread badge.
class Webhooks::Clickup::ProcessEventService
  TICKET_UPDATED_EVENT = 'ticket.updated'.freeze

  def initialize(payload)
    @payload = payload.is_a?(Hash) ? payload.with_indifferent_access : {}
  end

  def perform
    task_id = @payload[:task_id]
    return if task_id.blank?

    ticket = Ticket.find_by(clickup_task_id: task_id)
    return if ticket.nil?

    case @payload[:event]
    when 'taskStatusUpdated'
      apply_status_update(ticket)
    when 'taskCustomFieldUpdated'
      apply_custom_field_update(ticket)
    end
  end

  private

  # ClickUp payload shape (abbreviated):
  #   { event: 'taskStatusUpdated', task_id: '...',
  #     history_items: [{ field: 'status', after: { id, status, type }, ... }] }
  def apply_status_update(ticket)
    latest = Array(@payload[:history_items]).find { |h| h[:field] == 'status' }
    return if latest.blank?

    new_status_id = latest.dig(:after, :id)
    new_status_name = latest.dig(:after, :status)
    return if new_status_id.blank?
    return if ticket.clickup_status_id == new_status_id

    ticket.update!(
      clickup_status_id: new_status_id,
      clickup_status_name: new_status_name
    )
    broadcast(ticket, notify: notifiable_transition?(new_status_name, latest.dig(:after, :type)))
  end

  # `taskCustomFieldUpdated` fires for every custom field change; we only
  # care about the "Resposta para o Cliente" field. Everything else is
  # dropped silently so this handler stays O(1).
  def apply_custom_field_update(ticket)
    latest = Array(@payload[:history_items]).find { |h| h[:field] == 'custom_field' }
    return if latest.blank?

    field_id = latest.dig(:custom_field, :id)
    return unless field_id == Integrations::Clickup::FieldMap::FIELDS[:resposta_para_cliente]

    new_value = extract_text_value(latest[:after])
    return if new_value.nil?
    return if ticket.resposta_para_cliente == new_value

    ticket.update!(resposta_para_cliente: new_value, resposta_notified_at: Time.current)
    # A brand-new customer-facing response is always worth a toast — the
    # ops team wrote it specifically for the operator to relay.
    broadcast(ticket, notify: true)
  end

  # ClickUp `after` for a text custom field is a hash like { value: "..." },
  # but the exact shape depends on the field type — normalize here.
  def extract_text_value(after)
    return nil if after.nil?
    return after if after.is_a?(String)
    return after[:value] if after.is_a?(Hash) && after.key?(:value)

    nil
  end

  def notifiable_transition?(status_name, status_type)
    slug = status_name.to_s.strip.downcase
    return true if Integrations::Clickup::FieldMap::NOTIFIABLE_STATUS_SLUGS.include?(slug)

    Integrations::Clickup::FieldMap::TERMINAL_STATUS_TYPES.include?(status_type.to_s)
  end

  def broadcast(ticket, notify:)
    tokens = broadcast_tokens_for(ticket)
    return if tokens.blank?

    ::ActionCableBroadcastJob.perform_later(
      tokens.uniq,
      TICKET_UPDATED_EVENT,
      {
        account_id: ticket.account_id,
        ticket: ticket.push_event_data,
        notify: notify
      }
    )
  end

  # Owner gets every update; administrators of the same account get them too
  # because they see the full Meus Tickets list. Agents outside the owner
  # never see other agents' tickets so their tokens are excluded.
  def broadcast_tokens_for(ticket)
    tokens = []
    tokens << ticket.user.pubsub_token if ticket.user&.pubsub_token.present?
    tokens.concat(ticket.account.administrators.pluck(:pubsub_token))
    tokens.compact_blank
  end
end
