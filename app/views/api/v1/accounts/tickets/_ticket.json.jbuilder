json.id ticket.id
json.display_id ticket.display_id
json.account_id ticket.account_id
json.conversation_id ticket.conversation_id
json.conversation_display_id ticket.conversation&.display_id
json.message_id ticket.context_id if ticket.context_type == 'Message'
json.relatar_problema ticket.relatar_problema
json.comportamento_esperado ticket.comportamento_esperado

json.sync_status ticket.sync_status
json.sync_error ticket.sync_error
json.clickup_task_id ticket.clickup_task_id
json.clickup_task_url ticket.clickup_task_url
json.clickup_status_id ticket.clickup_status_id
json.clickup_status_name ticket.clickup_status_name

json.resposta_para_cliente ticket.resposta_para_cliente
json.resposta_notified_at ticket.resposta_notified_at

json.updates ticket.ticket_updates_payload

json.user do
  # `user` is nullable — a removed agent still has historic tickets, and we
  # want the manager view to keep rendering "Agente" even after the seat is
  # freed. The frontend renders "—" when the whole user block is null.
  if ticket.user
    json.id ticket.user.id
    json.name ticket.user.name
    json.email ticket.user.email
  else
    json.null!
  end
end

json.created_at ticket.created_at
json.updated_at ticket.updated_at
