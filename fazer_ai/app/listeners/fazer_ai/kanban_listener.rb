# frozen_string_literal: true

class FazerAi::KanbanListener < BaseListener
  def conversation_created(event)
    conversation = event.data[:conversation]
    return unless conversation&.account&.kanban_feature_enabled?

    auto_create_task_for_conversation(conversation)
  end

  def conversation_resolved(event)
    conversation = event.data[:conversation]
    return unless conversation&.account&.kanban_feature_enabled?

    auto_complete_task_on_conversation_resolve(conversation)
  end

  def conversation_updated(event)
    conversation = event.data[:conversation]
    changed_attributes = event.data[:changed_attributes]
    return unless conversation&.account&.kanban_feature_enabled?
    return unless changed_attributes

    sync_conversation_assignee_to_task(conversation, changed_attributes)
  end

  def kanban_task_created(event)
    task = event.data[:task]
    return unless task&.account&.kanban_feature_enabled?

    auto_assign_task_to_agent(task)
  end

  def kanban_task_updated(event)
    task = event.data[:task]
    changed_attributes = event.data[:changed_attributes]
    return unless task&.account&.kanban_feature_enabled?
    return unless changed_attributes

    auto_resolve_conversations_on_task_end(task, changed_attributes)
  end

  private

  def auto_assign_task_to_agent(task)
    FazerAi::Kanban::TaskAutoAssignmentService.new(task: task).perform
  end

  def auto_resolve_conversations_on_task_end(task, changed_attributes)
    return unless changed_attributes['board_step_id']
    return unless task.board.auto_resolve_conversation_on_task_end?
    return unless task.status.in?(%w[completed cancelled])

    Current.executed_by = FazerAi::Kanban::TaskAutomation.new(task: task)
    task.conversations.where.not(status: 'resolved').find_each(&:resolved!)
  ensure
    Current.executed_by = nil
  end

  def auto_complete_task_on_conversation_resolve(conversation)
    task = conversation.kanban_task
    return unless task
    return unless task.board.auto_complete_task_on_conversation_resolve?
    return if task.status.in?(%w[completed cancelled])

    completed_step = task.board.completed_step
    return unless completed_step

    task.update!(board_step: completed_step)
  end

  def sync_conversation_assignee_to_task(conversation, changed_attributes)
    return unless changed_attributes['assignee_id']

    task = conversation.kanban_task
    return unless task_syncable?(task)

    perform_agent_sync(task, changed_attributes['assignee_id'])
  end

  def task_syncable?(task)
    task&.board&.sync_task_and_conversation_agents?
  end

  def perform_agent_sync(task, assignee_change)
    old_assignee_id, new_assignee_id = assignee_change

    changed = remove_agent_from_task(task, old_assignee_id) if old_assignee_id.present?
    changed = add_agent_to_task(task, new_assignee_id) || changed if new_assignee_id.present?

    dispatch_task_update(task) if changed
  end

  def remove_agent_from_task(task, agent_id)
    task_agent = task.task_agents.find_by(agent_id: agent_id)
    return false unless task_agent

    task_agent.skip_sync_callbacks = true
    task_agent.destroy!
    true
  end

  def add_agent_to_task(task, agent_id)
    return false if task.task_agents.exists?(agent_id: agent_id)
    return false unless task.board.assigned_agents.exists?(id: agent_id)

    task.task_agents.create!(agent_id: agent_id, skip_sync_callbacks: true)
    true
  end

  def dispatch_task_update(task)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::KANBAN_TASK_UPDATED,
      Time.zone.now,
      task: task.reload,
      changed_attributes: {}
    )
  end

  def auto_create_task_for_conversation(conversation)
    inbox = conversation.inbox
    account = conversation.account

    boards_for_inbox(inbox).each do |board|
      next unless board.auto_create_task_for_conversation?
      next if board.first_step.blank?

      create_task_for_conversation(board, conversation, account)
    end
  end

  def boards_for_inbox(inbox)
    FazerAi::Kanban::Board
      .joins(:board_inboxes)
      .where(kanban_board_inboxes: { inbox_id: inbox.id })
  end

  def create_task_for_conversation(board, conversation, account)
    title = generate_task_title(conversation, account)

    task = FazerAi::Kanban::Task.create!(
      account: account,
      board: board,
      board_step: board.first_step,
      creator: nil,
      title: title,
      conversation_ids: [conversation.display_id]
    )

    assign_conversation_agent_to_task(task, conversation, board)
  end

  def assign_conversation_agent_to_task(task, conversation, board)
    agent = conversation.assignee
    return unless agent
    return unless board.assigned_agents.include?(agent)

    task.assigned_agents << agent
  end

  def generate_task_title(conversation, account)
    contact_name = conversation.contact&.name.presence || I18n.t('kanban.tasks.auto_create.unknown_contact', locale: account.locale)

    I18n.t(
      'kanban.tasks.auto_create.title',
      locale: account.locale,
      display_id: conversation.display_id,
      contact_name: contact_name
    )
  end
end
