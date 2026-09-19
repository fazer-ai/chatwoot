# A wait on inactivity is armed, not run: it writes a clock, and writing the same clock twice
# writes the same clock. That is why it does not go through the message run claims, which exist to
# keep an action from happening twice and, applied to an arm, suppress real activity: an edit that
# restores a body the rule already saw reuses that body's finished claim, and the deadline that
# should have moved never does. Nothing here is customer-facing, so there is nothing to deduplicate.
class AutomationRules::InactivityArmingService
  def initialize(message)
    @message = message
    @conversation = message.conversation
    @account = message.account
  end

  def perform
    return if @account.blank? || !@account.feature_enabled?('delayed_automations')

    rules.each do |rule|
      next if AutomationRules::ConditionsFilterService.new(rule, @conversation, {}).perform.blank?

      AutomationRulePendingExecution.schedule(rule: rule, conversation: @conversation, message: @message)
    end
  end

  private

  # Conversation-level rules, so the conditions are asked of the conversation and not of the
  # message that happened to arm them.
  def rules
    AutomationRule.where(account_id: @account.id, event_name: 'conversation_updated',
                         active: true, execution_delay_trigger: 'inactivity')
  end
end
