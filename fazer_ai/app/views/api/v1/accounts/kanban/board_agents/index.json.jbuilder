json.agents do
  json.array! @agents do |agent|
    json.partial! 'api/v1/accounts/kanban/board_agents/board_agent', agent: agent
  end
end
