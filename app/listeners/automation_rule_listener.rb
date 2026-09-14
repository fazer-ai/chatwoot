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
    # Before the rules, not after: a recovery arriving in between has to find the arrival on record, and
    # the claims are what keep it from repeating whatever this evaluation is about to do.
    track_arrival(event.data[:message])
    process_message_event(event)
  end

  # The body of a message that was stored before it could be read has arrived into that same row. Rules
  # are evaluated again, against the content this time: a rule filtered on it never saw a body at the
  # arrival, and MESSAGE_UPDATED reaches no automation (fazer-ai/chatwoot#491).
  #
  # Re-firing `message_created` instead would run every rule that does not filter on content a second
  # time, which is worse than the miss: an auto-reply answering twice, a webhook delivered twice.
  # Only for a placeholder whose arrival this mechanism handled. A row stored before this was deployed,
  # or before its record expired, ran its rules with no claim written, so evaluating again would run the
  # ones that do not filter on content a second time: an auto-reply answering a message from before the
  # upgrade, which is the outcome this whole design exists to avoid. Then the content is the only thing
  # missed, which is what every such row had already settled for.
  def message_recovered(event)
    return unless arrival_tracked?(event.data[:message])

    process_message_event(event)
  end

  # Somebody changed what a message says, and the rules that answer to it are the ones whose trigger is
  # this event: a rule opts in, rather than every `message_created` rule being asked a second question.
  # An edit is not a second arrival, and the difference is visible in the actions -- an auto-reply
  # answering a typo correction is the outcome that keeps this off `message_created` (#648).
  def message_edited(event)
    process_message_event(event, 'message_edited')
  end

  private

  def process_message_event(event, event_name = 'message_created')
    message = event.data[:message]

    return if ignore_message_created_event?(event)

    account = message.try(:account)
    changed_attributes = event.data[:changed_attributes]

    return unless rule_present?(event_name, account)

    rules = current_account_rules(event_name, account)

    rules.each do |rule|
      claimed = claim_matching_rule(rule, message, event_name, changed_attributes)

      execute_claimed_rule(rule, account, message, claimed[:key], claimed[:token]) if claimed[:token]
    end
  end

  # The body the conditions answered about and the body the claim is taken on have to be the same one.
  # They are read separately -- the conditions by a query, the key off the row this job loaded -- and an
  # edit committing between the two would have this execution claim the older body's key while acting on
  # the newer one, leaving the newer body's own key free for a second run of the same rule.
  #
  # The row lock is held for that pair only, and only where the key is about the body: the arrival and
  # the recovery key on the message, which does not move, and pay nothing. The actions always run
  # outside it, because they send messages and call webhooks.
  def claim_matching_rule(rule, message, event_name, changed_attributes)
    return evaluate_and_claim(rule, message, event_name, changed_attributes) unless event_name == 'message_edited'

    message.with_lock { evaluate_and_claim(rule, message, event_name, changed_attributes) }
  end

  # The claim is asked for after the conditions and only when they match, never before: a rule that did
  # not match while the row was a placeholder has to be left free to run when the content arrives.
  #
  # `present?` rather than `blank?`, because that is the question the rule's own filter answers and the
  # two differ for anything that defines only one of them.
  def evaluate_and_claim(rule, message, event_name, changed_attributes)
    conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, message.conversation,
                                                                      { message: message, changed_attributes: changed_attributes }).perform
    return {} unless conditions_match.present? # rubocop:disable Rails/Blank -- see the note above: not the same question

    key = claim_key_for(event_name, rule, message)

    { key: key, token: claim(key) }
  end

  # What the claim is about, and the two events answer it differently.
  #
  # For the arrival and the recovery it is the message: the two are one message becoming readable once,
  # so a rule runs for it once.
  #
  # For an edit it is the body. "Has this rule already run for this message" would let only the first of
  # two edits run, and two edits are two events. "Has this rule already run for this message against
  # this body" keeps both of those and still answers for the case that costs a duplicate action: two
  # edits committing before either job runs leave both evaluations reading the same stored body, since
  # the conditions are asked of the row and not of the event, and they are then the same run. The cost
  # is an edit that restores a body this rule already ran on, which does not run again.
  def claim_key_for(event_name, rule, message)
    return claim_key(rule, message) unless event_name == 'message_edited'

    format(Redis::RedisKeys::AUTOMATION_RULE_MESSAGE_BODY_RUN, rule_id: rule.id, message_id: message.id,
                                                               body: Digest::SHA256.hexdigest(message.content.to_s)[0, 16])
  end

  # At most one execution of this rule for this message, counting the arrival and the recovery that
  # filled a placeholder in. Claimed on both paths and not only on the recovery: nothing orders the two
  # jobs, so the arrival may well be the one that evaluates after the content landed, and a claim it
  # skipped is one the recovery would take for a rule that already ran.
  #
  # Atomic, because both may find the same rule matching; the one that takes the key is the one that
  # acts. Answers false when the key is already there. A key lost before the recovery (an expiry, a
  # Redis that was replaced) costs a second run of that one rule, which is why the window is long.
  # Answers this attempt's own token when it took the key, and nothing when the key was already there,
  # which is the rule having run.
  #
  # The token is what makes the release safe. When the answer to the write is what was lost, Redis may
  # well have taken the key, and a claim nobody could read is a rule that never ran holding its own
  # record for thirty days. But the key may equally belong to an execution that already happened -- the
  # arrival's, with the recovery now asking -- and deleting that one would let the retry run the rule a
  # second time. So only a key carrying this attempt's token is released.
  def claim(key)
    token = SecureRandom.uuid
    taken = Redis::Alfred.set(key, token, nx: true, ex: RULE_RUN_CLAIM_EXPIRY)

    token if taken
  rescue StandardError
    release_claim(key, token)
    raise
  end

  # A rule whose execution raised before it did anything must be free to run on the retry of this job:
  # holding the claim would spend the whole window on an attempt that never acted, and for a delayed rule
  # the attempt is only a row in `automation_rule_pending_executions`, which failed to be written.
  # Releasing restores exactly what happens today, where a retry evaluates and acts again.
  def execute_claimed_rule(rule, account, message, key, token)
    execute_rule(rule, account, message.conversation, message: message)
  rescue StandardError
    release_claim(key, token)
    raise
  end

  # Best effort on the way out of a failure that is already being raised: a delete that fails too would
  # replace the error the caller needs to see with one about Redis.
  def release_claim(key, token)
    Redis::Alfred.delete_if_equals(key, token)
  rescue StandardError => e
    Rails.logger.warn("[AUTOMATION] could not release the run claim #{key}: #{e.message}")
  end

  def claim_key(rule, message)
    format(Redis::RedisKeys::AUTOMATION_RULE_MESSAGE_RUN, rule_id: rule.id, message_id: message.id)
  end

  # Recorded for a placeholder only, which is the only row a recovery can follow, so the ordinary message
  # pays nothing for this.
  def track_arrival(message)
    return unless placeholder?(message)

    Redis::Alfred.set(arrival_key(message), Time.current.to_i, ex: RULE_RUN_CLAIM_EXPIRY)
  end

  def arrival_tracked?(message)
    Redis::Alfred.exists?(arrival_key(message))
  end

  def arrival_key(message)
    format(Redis::RedisKeys::AUTOMATION_MESSAGE_ARRIVAL_TRACKED, message_id: message.id)
  end

  # A row stored for a message this side could not read yet. `unsupported_reason` is written by the
  # WhatsApp session layer alone, and only for a body that may still arrive under the same id.
  def placeholder?(message)
    message.try(:content_attributes).to_h['unsupported_reason'].present?
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
