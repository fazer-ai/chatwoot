# frozen_string_literal: true

class FazerAi::Kanban::BoardRoundRobinService
  pattr_initialize [:board!]

  def clear_queue
    ::Redis::Alfred.delete(round_robin_key)
  end

  def add_agent_to_queue(user_id)
    ::Redis::Alfred.lpush(round_robin_key, user_id)
  end

  def remove_agent_from_queue(user_id)
    ::Redis::Alfred.lrem(round_robin_key, user_id)
  end

  def reset_queue
    clear_queue
    add_agent_to_queue(board.board_agents.map(&:agent_id))
  end

  def available_agent(allowed_agent_ids: [])
    reset_queue unless validate_queue?
    user_id = get_member_from_allowed_agent_ids(allowed_agent_ids)
    board.assigned_agents.find_by(id: user_id) if user_id.present?
  end

  private

  def get_member_from_allowed_agent_ids(allowed_agent_ids)
    return nil if allowed_agent_ids.blank?

    user_id = queue.intersection(allowed_agent_ids).pop
    pop_push_to_queue(user_id)
    user_id
  end

  def pop_push_to_queue(user_id)
    return if user_id.blank?

    remove_agent_from_queue(user_id)
    add_agent_to_queue(user_id)
  end

  def validate_queue?
    board.board_agents.map(&:agent_id).sort == queue.map(&:to_i).sort
  end

  def queue
    ::Redis::Alfred.lrange(round_robin_key)
  end

  def round_robin_key
    format(::Redis::Alfred::KANBAN_BOARD_ROUND_ROBIN_AGENTS, board_id: board.id)
  end
end
