# frozen_string_literal: true

module FazerAi::ActionCableListener
  include Events::Types

  def kanban_task_created(event)
    task = event.data[:task]
    account = task.account
    tokens = task_listener_tokens(account, task)

    broadcast(account, tokens, KANBAN_TASK_CREATED, task.push_event_data)
  end

  def kanban_task_updated(event)
    task = event.data[:task]
    account = task.account
    tokens = task_listener_tokens(account, task)

    broadcast(account, tokens, KANBAN_TASK_UPDATED, task.push_event_data)
  end

  def kanban_task_deleted(event)
    task_data = event.data[:task]

    if task_data.is_a?(Hash)
      account = Account.find(task_data[:account_id])
      board = FazerAi::Kanban::Board.find_by(id: task_data[:board_id])
      tokens = if board
                 (board.assigned_agents.pluck(:pubsub_token) + account.administrators.pluck(:pubsub_token)).uniq
               else
                 account.administrators.pluck(:pubsub_token)
               end
      broadcast(account, tokens, KANBAN_TASK_DELETED, { id: task_data[:id], board_id: task_data[:board_id] })
    else
      task = task_data
      account = task.account
      tokens = task_listener_tokens(account, task)
      broadcast(account, tokens, KANBAN_TASK_DELETED, { id: task.id, board_id: task.board_id })
    end
  end

  def kanban_step_created(event)
    step = event.data[:step]
    account = step.board.account
    tokens = step_listener_tokens(account, step)

    broadcast(account, tokens, KANBAN_STEP_CREATED, step.push_event_data)
  end

  def kanban_step_updated(event)
    step = event.data[:step]
    account = step.board.account
    tokens = step_listener_tokens(account, step)

    broadcast(account, tokens, KANBAN_STEP_UPDATED, step.push_event_data)
  end

  def kanban_board_updated(event)
    board = event.data[:board]
    account = board.account
    tokens = board_listener_tokens(account, board)

    broadcast(account, tokens, KANBAN_BOARD_UPDATED, board.push_event_data)
  end

  private

  def task_listener_tokens(account, task)
    board_agent_tokens = task.board.assigned_agents.pluck(:pubsub_token)
    admin_tokens = account.administrators.pluck(:pubsub_token)
    (board_agent_tokens + admin_tokens).uniq
  end

  def step_listener_tokens(account, step)
    board_agent_tokens = step.board.assigned_agents.pluck(:pubsub_token)
    admin_tokens = account.administrators.pluck(:pubsub_token)
    (board_agent_tokens + admin_tokens).uniq
  end

  def board_listener_tokens(account, board)
    board_agent_tokens = board.assigned_agents.pluck(:pubsub_token)
    admin_tokens = account.administrators.pluck(:pubsub_token)
    (board_agent_tokens + admin_tokens).uniq
  end
end
