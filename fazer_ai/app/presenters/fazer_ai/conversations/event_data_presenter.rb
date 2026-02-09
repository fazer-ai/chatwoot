# frozen_string_literal: true

module FazerAi::Conversations::EventDataPresenter
  def push_data
    data = super
    data[:kanban_task] = kanban_task.present? ? kanban_task_data : nil
    data
  end

  private

  def kanban_task_data # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    {
      id: kanban_task.id,
      account_id: kanban_task.account_id,
      board_id: kanban_task.board_id,
      board_step_id: kanban_task.board_step_id,
      board_step: {
        id: kanban_task.board_step.id,
        name: kanban_task.board_step.name,
        cancelled: kanban_task.board_step.cancelled,
        color: kanban_task.board_step.color
      },
      created_by_id: kanban_task.created_by_id,
      title: kanban_task.title,
      description: kanban_task.description,
      priority: kanban_task.priority,
      start_date: kanban_task.start_date,
      due_date: kanban_task.due_date,
      created_at: kanban_task.created_at,
      updated_at: kanban_task.updated_at,
      contact_ids: kanban_task.contact_ids,
      labels: kanban_task.cached_label_list_array,
      assigned_agents: kanban_task.assigned_agents.map do |agent|
        {
          id: agent.id,
          name: agent.name,
          avatar_url: agent.avatar_url,
          availability_status: agent.availability_status
        }
      end,
      creator: if kanban_task.creator.present?
                 {
                   id: kanban_task.creator.id,
                   name: kanban_task.creator.name
                 }
               end,
      creator_display_name: kanban_task.creator_display_name,
      board: {
        id: kanban_task.board.id,
        name: kanban_task.board.name,
        steps: kanban_task.board.ordered_steps.map do |step|
          {
            id: step.id,
            name: step.name,
            cancelled: step.cancelled,
            color: step.color
          }
        end,
        assigned_agents: kanban_task.board.assigned_agents.map do |agent|
          {
            id: agent.id,
            name: agent.name,
            avatar_url: agent.avatar_url,
            availability_status: agent.availability_status
          }
        end
      }
    }
  end
end
