# frozen_string_literal: true

class FazerAi::AutomationRules::KanbanActionService
  def initialize(rule, account, task)
    @rule = rule
    @account = account
    @task = task
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      @task.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def assign_agent(agent_ids = [])
    return if agent_ids.blank?

    agent_id = agent_ids.first
    return unassign_agent if agent_id == 'nil'

    agent = @account.users.find_by(id: agent_id)
    return if agent.blank?
    return unless @task.board.assigned_agents.exists?(id: agent.id)

    @task.task_agents.find_or_create_by!(agent: agent)

    assign_agent_to_conversations(agent) if @task.conversations.any?
  end

  def move_to_step(step_ids = [])
    return if step_ids.blank?

    step_id = step_ids.first
    step = @task.board.steps.find_by(id: step_id)
    return if step.blank?

    @task.update!(board_step: step)
  end

  def mark_completed(_params = nil)
    completed_step = @task.board.completed_step
    return if completed_step.blank?

    @task.update!(board_step: completed_step)
  end

  def mark_cancelled(_params = nil)
    # NOTE: Board might have multiple cancelled steps, picking the first one
    cancelled_step = @task.board.ordered_steps.find_by(cancelled: true)
    return if cancelled_step.blank?

    @task.update!(board_step: cancelled_step)
  end

  def change_priority(priority_params = [])
    return if priority_params.blank?

    priority = priority_params.first
    return unless FazerAi::Kanban::Task::PRIORITIES.include?(priority)

    @task.update!(priority: priority)
  end

  def send_webhook_event(webhook_url)
    return if webhook_url.blank?

    payload = @task.push_event_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url.first, payload)
  end

  def send_message(message)
    return if message.blank?

    @task.conversations.each do |conversation|
      next if conversation_a_tweet?(conversation)

      params = { content: message.first, private: false, content_attributes: { automation_rule_id: @rule.id } }
      Messages::MessageBuilder.new(nil, conversation, params).perform
    end
  end

  def add_private_note(message)
    return if message.blank?

    @task.conversations.each do |conversation|
      next if conversation_a_tweet?(conversation)

      params = { content: message.first, private: true, content_attributes: { automation_rule_id: @rule.id } }
      Messages::MessageBuilder.new(nil, conversation.reload, params).perform
    end
  end

  def unassign_agent
    @task.task_agents.destroy_all
  end

  def assign_agent_to_conversations(agent)
    @task.conversations.each do |conversation|
      next if conversation.assignee_id == agent.id
      next unless conversation.inbox.members.exists?(id: agent.id) || @account.administrators.exists?(id: agent.id)

      conversation.update!(assignee_id: agent.id)
    end
  end

  def conversation_a_tweet?(conversation)
    return false if conversation.additional_attributes.blank?

    conversation.additional_attributes['type'] == 'tweet'
  end
end
