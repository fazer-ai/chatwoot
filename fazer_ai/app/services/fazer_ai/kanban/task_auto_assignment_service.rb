# frozen_string_literal: true

class FazerAi::Kanban::TaskAutoAssignmentService
  pattr_initialize [:task!]

  def perform
    return if task.assigned_agents.any?
    return unless task.board.auto_assign_task_to_agent?

    new_assignee = find_assignee
    return unless new_assignee

    task.assigned_agents << new_assignee
    dispatch_task_updated_event
  end

  def find_assignee
    round_robin_service.available_agent(allowed_agent_ids: allowed_online_agent_ids)
  end

  private

  def dispatch_task_updated_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_TASK_UPDATED,
      Time.zone.now,
      task: task,
      changed_attributes: { 'assigned_agent_ids' => [[], task.assigned_agent_ids] }
    )
  end

  def online_agent_ids
    online_agents = OnlineStatusTracker.get_available_users(task.account_id)
    online_agents&.select { |_key, value| value.eql?('online') }&.keys
  end

  def allowed_online_agent_ids
    @allowed_online_agent_ids ||= online_agent_ids & board_agent_ids.map(&:to_s)
  end

  def board_agent_ids
    task.board.board_agents.pluck(:agent_id)
  end

  def round_robin_service
    @round_robin_service ||= FazerAi::Kanban::BoardRoundRobinService.new(board: task.board)
  end
end
