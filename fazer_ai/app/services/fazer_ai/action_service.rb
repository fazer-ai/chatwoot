# frozen_string_literal: true

module FazerAi::ActionService
  def assign_to_board(board_ids = [])
    return if board_ids.blank?

    board_id = board_ids.first
    board = @account.kanban_boards.find_by(id: board_id)
    return if board.blank?

    # NOTE: Reload to check if task was already created (e.g., by move_to_step executing this first)
    @conversation.reload
    return if @conversation.kanban_task&.board_id == board.id

    return unless board.inboxes.exists?(id: @conversation.inbox_id)

    title = generate_task_title(@conversation)
    task = FazerAi::Kanban::Task.create!(
      account: @account,
      board: board,
      board_step: board.first_step,
      creator: nil,
      title: title,
      conversation_ids: [@conversation.display_id]
    )

    assign_conversation_agent_to_task(task, @conversation, board)

    task
  end

  def move_to_step(step_ids = [])
    return if step_ids.blank?

    step_id = step_ids.first

    # NOTE: If conversation doesn't have a task yet, check if there's an assign_to_board action
    # and execute it first (handles case where move_to_step comes before assign_to_board)
    ensure_task_exists_from_actions if @conversation.kanban_task.blank?

    @conversation.reload
    task = @conversation.kanban_task
    return if task.blank?

    step = task.board.steps.find_by(id: step_id)
    return if step.blank?

    task.update!(board_step: step)
  end

  def add_label_to_task(labels)
    return if labels.blank?

    task = @conversation.kanban_task
    return if task.blank?

    task.add_labels(labels)
  end

  def remove_label_from_task(labels)
    return if labels.blank?

    task = @conversation.kanban_task
    return if task.blank?

    remaining_labels = task.label_list - labels
    task.update!(label_list: remaining_labels)
  end

  private

  def ensure_task_exists_from_actions
    return unless defined?(@rule) && @rule.present?

    assign_action = @rule.actions.find { |a| a.with_indifferent_access[:action_name] == 'assign_to_board' }
    return if assign_action.blank?

    assign_to_board(assign_action.with_indifferent_access[:action_params])
  end

  def generate_task_title(conversation)
    contact_name = conversation.contact&.name.presence || I18n.t('kanban.tasks.auto_create.unknown_contact', locale: @account.locale)

    I18n.t(
      'kanban.tasks.auto_create.title',
      locale: @account.locale,
      display_id: conversation.display_id,
      contact_name: contact_name
    )
  end

  def assign_conversation_agent_to_task(task, conversation, board)
    agent = conversation.assignee
    return unless agent
    return unless board.assigned_agents.include?(agent)

    task.assigned_agents << agent
  end
end
