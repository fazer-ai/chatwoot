json.extract! board,
              :id,
              :account_id,
              :name,
              :description,
              :settings,
              :steps_order,
              :created_at,
              :updated_at

json.assigned_inbox_ids board.inboxes.ids
json.assigned_inboxes do
  json.array! board.inboxes do |inbox|
    json.id inbox.id
    json.name inbox.name
    json.channel_type inbox.channel_type
    json.provider inbox.channel.try(:provider)
    json.medium inbox.channel.try(:medium) if inbox.twilio?
  end
end
json.assigned_agent_ids board.assigned_agents.ids
json.assigned_agents do
  json.array! board.assigned_agents do |agent|
    json.id agent.id
    json.name agent.name
    json.email agent.email
    json.avatar_url agent.avatar_url
    json.availability_status agent.availability_status
  end
end

json.total_tasks_count(board.steps.sum(&:tasks_count))

json.steps_summary do
  json.array! board.ordered_steps do |step|
    json.id step.id
    json.name step.name
    json.color step.color
    json.tasks_count step.tasks_count
    json.cancelled step.cancelled
    json.inferred_task_status step.inferred_task_status
  end
end

if local_assigns[:with_steps]
  json.steps do
    json.array! board.ordered_steps do |step|
      json.partial! 'api/v1/accounts/kanban/board_steps/board_step', step: step
    end
  end
end
