# frozen_string_literal: true

class FazerAi::AutomationRules::KanbanConditionsFilterService
  def initialize(rule, task, options = {})
    @rule = rule
    @task = task
    @account = task.account
    @options = options
    @changed_attributes = options[:changed_attributes]
  end

  def perform
    return false unless rule_valid?

    @rule.conditions.all? do |condition|
      evaluate_condition(condition.with_indifferent_access)
    end
  rescue StandardError => e
    Rails.logger.error "Error in FazerAi::AutomationRules::KanbanConditionsFilterService: #{e.message}"
    Rails.logger.info "KanbanConditionsFilterService failed while processing rule #{@rule.id} for task #{@task.id}"
    false
  end

  private

  def rule_valid?
    @rule.active? && @rule.account_id == @account.id
  end

  def evaluate_condition(condition)
    attribute_key = condition[:attribute_key]
    filter_operator = condition[:filter_operator]
    values = condition[:values] || []

    case attribute_key
    when 'kanban_board_id'
      evaluate_board_condition(filter_operator, values)
    when 'kanban_step_id'
      evaluate_step_condition(filter_operator, values)
    when 'assignee_id'
      evaluate_assignee_condition(filter_operator, values)
    when 'inbox_id'
      evaluate_inbox_condition(filter_operator, values)
    when 'priority'
      evaluate_priority_condition(filter_operator, values)
    else
      true
    end
  end

  def evaluate_board_condition(operator, values)
    case operator
    when 'equal_to'
      values.map(&:to_i).include?(@task.board_id)
    when 'not_equal_to'
      values.map(&:to_i).exclude?(@task.board_id)
    else
      true
    end
  end

  def evaluate_step_condition(operator, values)
    case operator
    when 'equal_to'
      values.map(&:to_i).include?(@task.board_step_id)
    when 'not_equal_to'
      values.map(&:to_i).exclude?(@task.board_step_id)
    else
      true
    end
  end

  def evaluate_assignee_condition(operator, values)
    task_agent_ids = @task.assigned_agents.pluck(:id)

    case operator
    when 'equal_to'
      values.map(&:to_i).intersect?(task_agent_ids)
    when 'not_equal_to'
      !values.map(&:to_i).intersect?(task_agent_ids)
    when 'is_present'
      task_agent_ids.any?
    when 'is_not_present'
      task_agent_ids.empty?
    else
      true
    end
  end

  def evaluate_inbox_condition(operator, values)
    task_inbox_ids = @task.conversations.pluck(:inbox_id).uniq

    case operator
    when 'equal_to'
      values.map(&:to_i).intersect?(task_inbox_ids)
    when 'not_equal_to'
      !values.map(&:to_i).intersect?(task_inbox_ids)
    when 'is_present'
      task_inbox_ids.any?
    when 'is_not_present'
      task_inbox_ids.empty?
    else
      true
    end
  end

  def evaluate_priority_condition(operator, values)
    case operator
    when 'equal_to'
      values.include?(@task.priority)
    when 'not_equal_to'
      values.exclude?(@task.priority)
    else
      true
    end
  end
end
