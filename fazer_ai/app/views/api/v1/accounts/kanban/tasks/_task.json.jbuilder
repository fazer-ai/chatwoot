json.extract! task,
              :id,
              :account_id,
              :board_id,
              :board_step_id,
              :created_by_id,
              :title,
              :description,
              :priority,
              :start_date,
              :due_date,
              :step_changed_at,
              :created_at,
              :updated_at

json.status task.status
json.date_status task.date_status
json.contact_ids task.contact_ids
json.conversation_ids task.conversation_ids
json.labels task.cached_label_list_array

json.contacts task.contacts do |contact|
  json.id contact.id
  json.name contact.name
  json.email contact.email
  json.avatar_url contact.avatar_url
end

json.conversations task.conversations do |conversation|
  json.id conversation.id
  json.display_id conversation.display_id
  json.status conversation.status
  json.inbox do
    json.id conversation.inbox.id
    json.name conversation.inbox.name
    json.channel_type conversation.inbox.channel_type
    json.provider conversation.inbox.channel.try(:provider)
    json.medium conversation.inbox.channel.try(:medium) if conversation.inbox.twilio?
  end
  json.contact do
    json.id conversation.contact.id
    json.name conversation.contact.name
    json.avatar_url conversation.contact.avatar_url
  end
end

json.assigned_agents task.assigned_agents do |agent|
  json.id agent.id
  json.name agent.name
  json.avatar_url agent.avatar_url
  json.availability_status agent.availability_status
end

if task.creator.present?
  json.creator do
    json.id task.creator.id
    json.name task.creator.name
  end
else
  json.creator nil
end

json.board do
  json.id task.board.id
  json.name task.board.name
  json.steps task.board.ordered_steps do |step|
    json.id step.id
    json.name step.name
    json.color step.color
  end
  json.assigned_agents task.board.assigned_agents do |agent|
    json.id agent.id
    json.name agent.name
    json.avatar_url agent.avatar_url
    json.availability_status agent.availability_status
  end
end
