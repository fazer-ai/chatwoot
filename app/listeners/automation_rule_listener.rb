class AutomationRuleListener < BaseListener
  # How long a rule execution on a message is remembered, which is what a later recovery of that message
  # reads to know the rule already ran. The message a placeholder stands for arrives when the sender's
  # phone comes back online to encrypt it again, so days later is normal and there is no upper bound
  # worth honouring: past this, a recovery may run that one rule a second time.
  RULE_RUN_CLAIM_EXPIRY = 30.days

  def conversation_updated(event)
    process_conversation_event(event, 'conversation_updated')
  end

  def conversation_created(event)
    process_conversation_event(event, 'conversation_created')
  end

  def conversation_opened(event)
    process_conversation_event(event, 'conversation_opened')
  end

  def conversation_resolved(event)
    process_conversation_event(event, 'conversation_resolved')
  end

  def message_created(event)
    process_message_event(event)
  end

  # The body of a message that was stored before it could be read has arrived into that same row. Rules
  # are evaluated again, against the content this time: a rule filtered on it never saw a body at the
  # arrival, and MESSAGE_UPDATED reaches no automation (fazer-ai/chatwoot#491).
  #
  # Re-firing `message_created` instead would run every rule that does not filter on content a second
  # time, which is worse than the miss: an auto-reply answering twice, a webhook delivered twice.
  def message_recovered(event)
    process_message_event(event)
  end

  private

  def process_message_event(event)
    message = event.data[:message]

    return if ignore_message_created_event?(event)

    account = message.try(:account)
    changed_attributes = event.data[:changed_attributes]

    return unless rule_present?('message_created', account)

    rules = current_account_rules('message_created', account)

    rules.each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, message.conversation,
                                                                        { message: message, changed_attributes: changed_attributes }).perform
      # The claim is asked for after the conditions and only when they match, never before: a rule that
      # did not match while the row was a placeholder has to be left free to run when the content
      # arrives.
      execute_rule(rule, account, message.conversation, message: message) if conditions_match.present? && claim(rule, message)
    end
  end

  # At most one execution of this rule for this message, counting the arrival and the recovery that
  # filled a placeholder in. Claimed on both paths and not only on the recovery: nothing orders the two
  # jobs, so the arrival may well be the one that evaluates after the content landed, and a claim it
  # skipped is one the recovery would take for a rule that already ran.
  #
  # Atomic, because both may find the same rule matching; the one that takes the key is the one that
  # acts. Answers false when the key is already there. A key lost before the recovery (an expiry, a
  # Redis that was replaced) costs a second run of that one rule, which is why the window is long.
  def claim(rule, message)
    Redis::Alfred.set(
      format(Redis::RedisKeys::AUTOMATION_RULE_MESSAGE_RUN, rule_id: rule.id, message_id: message.id),
      Time.current.to_i, nx: true, ex: RULE_RUN_CLAIM_EXPIRY
    )
  end

  def process_conversation_event(event, event_name)
    return if performed_by_automation?(event)

    auto_reply_skip_events = %w[conversation_created conversation_opened]
    return if auto_reply_skip_events.include?(event_name) && ignore_auto_reply_event?(event)

    conversation = event.data[:conversation]
    account = conversation.account
    changed_attributes = event.data[:changed_attributes]

    rules = conversation_rules(event_name, account)
    return if rules.blank?

    rules.each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, conversation, { changed_attributes: changed_attributes }).perform
      execute_rule(rule, account, conversation) if conditions_match.present?
    end
  end

  # A delayed conversation rule reads as "the conversation has been in this status for N minutes",
  # so a conversation created in that status must arm it too. Creation never dispatches
  # CONVERSATION_UPDATED, and both paths key the episode on the same status_changed_at, so a later
  # update arming the same episode is deduped by the unique index.
  def conversation_rules(event_name, account)
    rules = current_account_rules(event_name, account)
    return rules unless event_name == 'conversation_created'

    rules + current_account_rules('conversation_updated', account).where.not(execution_delay: nil)
  end

  # Delayed rules record a pending execution instead of acting; the sweep re-checks and
  # runs them at due time. Flag off means no arming and no immediate fallback — a delayed
  # message silently becoming instant is worse than skipping.
  def execute_rule(rule, account, conversation, message: nil)
    if rule.execution_delay.present?
      return unless account.feature_enabled?('delayed_automations')

      AutomationRulePendingExecution.schedule(rule: rule, conversation: conversation, message: message)
    else
      ::AutomationRules::ActionService.new(rule, account, conversation).perform
    end
  end

  def rule_present?(event_name, account)
    return false if account.blank?

    current_account_rules(event_name, account).any?
  end

  def current_account_rules(event_name, account)
    AutomationRule.where(
      event_name: event_name,
      account_id: account.id,
      active: true
    )
  end

  def performed_by_automation?(event)
    event.data[:performed_by].present? && event.data[:performed_by].instance_of?(AutomationRule)
  end

  def ignore_auto_reply_event?(event)
    conversation = event.data[:conversation]
    conversation.additional_attributes['auto_reply'].present?
  end

  def ignore_message_created_event?(event)
    message = event.data[:message]
    performed_by_automation?(event) || message.activity? || message.auto_reply_email?
  end
end
