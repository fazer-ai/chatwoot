contact = conversation.contact
inbox = conversation.inbox
labels = Array(conversation.label_list)

json.id conversation.display_id
json.uuid conversation.uuid
json.status conversation.status
json.summary conversation.summary
json.created_at conversation.created_at.to_i
json.last_activity_at conversation.last_activity_at.to_i
json.labels labels
json.ai_enabled !labels.include?('agente-off')
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
