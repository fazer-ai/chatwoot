# Applies a ClickUp webhook event to the local Ticket.
#
# ClickUp fires a single `taskUpdated` umbrella event for every kind of task
# change (status, custom fields, priority, assignees, comments, etc.) with
# the concrete diff on the `history_items` array. We route on that array:
#
# - `field: 'status'`       → mirror ClickUp's status onto the Ticket
#                             (source of truth for the badge on Meus
#                             Tickets).
# - `field: 'custom_field'` → when the ops team fills the "Resposta para o
#                             Cliente" field, copy the new value onto the
#                             Ticket so it renders in the detail modal.
#
# Every other history-item field is dropped silently — Phase 1 only surfaces
# status + response back to the operator.
#
# After a change lands the service broadcasts `ticket.updated` on
# ActionCable so Meus Tickets refreshes live and, when the status
# transitions into `FieldMap::NOTIFIABLE_STATUS_SLUGS` (encerrado), the
# frontend fires a toast + bumps the sidebar unread badge.
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

    Array(@payload[:history_items]).each do |item|
      case item[:field]
      when 'status'
        apply_status_update(ticket, item)
      when 'custom_field'
        apply_custom_field_update(ticket, item)
      end
    end
  end

  private

  # `after` for a status change: { status, type: 'open'|'custom'|'done'|..., color, orderindex }.
  # ClickUp does NOT send a status id in the history_items payload — the
  # status is identified by name only. We dedup on the AurisChat canonical
  # mapped name so no-op broadcasts (e.g. "em andamento" → "aguardando
  # engenharia", both mapped to "em análise") don't wake the frontend.
  def apply_status_update(ticket, item)
    raw_status_name = item.dig(:after, :status)
    return if raw_status_name.blank?

    mapped_name = Integrations::Clickup::FieldMap.auris_status_for(raw_status_name)
    return if ticket.clickup_status_name == mapped_name

    ticket.update!(clickup_status_name: mapped_name)
    broadcast(ticket, notify: notifiable_transition?(mapped_name, item.dig(:after, :type)))
  end

  # We only care about the "Resposta para o Cliente" custom field.
  # Everything else (Ambiente, Canal, Chat ID, ...) is noise and would trash
  # the ticket's local state if we mirrored it back.
  def apply_custom_field_update(ticket, item)
    field_id = item.dig(:custom_field, :id)
    return unless field_id == Integrations::Clickup::FieldMap::FIELDS[:resposta_para_cliente]

    new_value = extract_text_value(item[:after])
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
