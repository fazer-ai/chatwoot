contact = conversation.contact
inbox = conversation.inbox
labels = Array(conversation.label_list)
funnel_stage = conversation.funnel_stage
loss_reason = nil
if funnel_stage&.requires_loss_reason?
  latest_change = conversation.account.funnel_stage_changes
                              .where(conversation_id: conversation.id, new_stage: funnel_stage.name)
                              .order(created_at: :desc)
                              .first
  loss_reason = latest_change&.loss_reason
end

json.id conversation.display_id
json.uuid conversation.uuid
json.status conversation.status
json.summary conversation.summary
json.created_at conversation.created_at.to_i
json.last_activity_at conversation.last_activity_at.to_i
json.labels labels
json.ai_enabled conversation.ai_status_enabled?
json.loss_reason loss_reason ? { id: loss_reason.id, name: loss_reason.name } : nil
json.contact do
  json.id contact.id
  json.name contact.name
  json.phone_number contact.phone_number
  json.thumbnail contact.avatar_url
end
json.inbox do
  json.id inbox.id
  json.name inbox.name
  json.channel_type inbox.channel_type
end
