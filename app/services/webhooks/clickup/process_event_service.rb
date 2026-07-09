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
# PR3 will layer notifications on top of this (bell + toast when the
# status transitions into one of FieldMap::NOTIFIABLE_STATUS_SLUGS).
class Webhooks::Clickup::ProcessEventService
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

    ticket.update!(resposta_para_cliente: new_value)
  end

  # ClickUp `after` for a text custom field is a hash like { value: "..." },
  # but the exact shape depends on the field type — normalize here.
  def extract_text_value(after)
    return nil if after.nil?
    return after if after.is_a?(String)
    return after[:value] if after.is_a?(Hash) && after.key?(:value)

    nil
  end
end
