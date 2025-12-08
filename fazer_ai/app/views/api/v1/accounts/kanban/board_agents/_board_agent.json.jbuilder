json.extract! agent,
              :id,
              :board_id,
              :agent_id,
              :created_at,
              :updated_at

if agent.agent.present?
  json.agent do
    json.id agent.agent.id
    json.name agent.agent.name
    json.email agent.agent.email
    json.avatar_url agent.agent.avatar_url
    json.availability_status agent.agent.availability_status
  end
else
  json.agent nil
end
