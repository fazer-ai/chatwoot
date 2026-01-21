# frozen_string_literal: true

class FazerAi::KanbanAutomationRuleListener < BaseListener
  def kanban_task_created(event)
    process_kanban_task_event(event, 'kanban_task_created')
  end

  def kanban_task_updated(event)
    process_kanban_task_event(event, 'kanban_task_updated')
  end

  def kanban_task_completed(event)
    process_kanban_task_event(event, 'kanban_task_completed')
  end

  def kanban_task_cancelled(event)
    process_kanban_task_event(event, 'kanban_task_cancelled')
  end

  private

  def process_kanban_task_event(event, event_name) # rubocop:disable Metrics/CyclomaticComplexity
    return if performed_by_automation?(event)

    task = event.data[:task]
    return unless task&.account&.kanban_feature_enabled?

    account = task.account
    changed_attributes = event.data[:changed_attributes]

    return unless kanban_rule_present?(event_name, account)

    rules = current_account_kanban_rules(event_name, account)

    rules.each do |rule|
      conditions_match = FazerAi::AutomationRules::KanbanConditionsFilterService.new(
        rule, task, { changed_attributes: changed_attributes }
      ).perform
      FazerAi::AutomationRules::KanbanActionService.new(rule, account, task).perform if conditions_match
    end
  end

  def kanban_rule_present?(event_name, account)
    return false if account.blank?

    current_account_kanban_rules(event_name, account).any?
  end

  def current_account_kanban_rules(event_name, account)
    AutomationRule.where(
      event_name: event_name,
      account_id: account.id,
      active: true
    )
  end

  def performed_by_automation?(event)
    event.data[:performed_by].present? && event.data[:performed_by].instance_of?(AutomationRule)
  end
end
