# frozen_string_literal: true

class FazerAi::Kanban::ApplicationPolicy < ApplicationPolicy
  private

  def feature_enabled?
    account&.kanban_feature_enabled?
  end

  def admin?
    account_user&.administrator?
  end

  def agent?
    account_user&.agent?
  end

  def user_assigned_to_board?(board)
    return false unless agent? && user && board

    board.board_agents.exists?(agent_id: user.id)
  end

  def accessible_board?(board = record)
    return false unless board

    board_scope_for(FazerAi::Kanban::Board).exists?(id: board.id)
  end

  def accessible_task?(task = record)
    return false unless task

    task_scope_for(FazerAi::Kanban::Task).exists?(id: task.id)
  end

  def agent_can_manage_board?(board)
    feature_enabled? && agent? && user_assigned_to_board?(board)
  end

  def task_owned_by_user?(task)
    return false unless user && task

    task.assigned_agent_ids.include?(user.id) || task.created_by_id == user.id
  end

  def board_scope_for(scope)
    return scope.none unless feature_enabled?

    scoped = scope.where(account_id: account.id)
    return scoped if admin?
    return scoped.none unless agent? && user

    scoped.joins(:board_agents)
          .where(kanban_board_agents: { agent_id: user.id })
          .distinct
  end

  def task_scope_for(scope)
    return scope.none unless feature_enabled?

    scoped = scope.where(account_id: account.id)
    return scoped if admin?
    return scoped.none unless agent? && user

    scoped.left_outer_joins(board: :board_agents)
          .left_outer_joins(:task_agents)
          .where(
            'kanban_board_agents.agent_id = :user_id OR ' \
            'kanban_task_agents.agent_id = :user_id OR ' \
            'kanban_tasks.created_by_id = :user_id',
            user_id: user.id
          ).distinct
  end
end
