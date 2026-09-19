class AutomationRules::ProcessPendingExecutionJob < ApplicationJob
  queue_as :medium

  discard_on ActiveJob::DeserializationError

  def perform(pending_execution)
    # Account flag off pauses (not skips): leave the row pending so re-enabling resumes it.
    return unless pending_execution.account.feature_enabled?('delayed_automations')
    # Atomic claim: a duplicate enqueue (overlapping sweep or stale reclaim) loses here and returns.
    return unless pending_execution.claim!
    # An inactivity wait is measured from the conversation's last activity, and some activity never
    # reaches a listener to re-arm the row. Push the clock instead of firing on a conversation that moved.
    return if reschedule_inactivity(pending_execution)

    skip_reason = skip_reason_for(pending_execution)
    return settle_skip(pending_execution, skip_reason) if skip_reason

    execute(pending_execution)
  rescue StandardError => e
    # Row stays `processing`; the next sweep reclaims and retries it once the lock goes stale.
    ChatwootExceptionTracker.new(e, account: pending_execution.account).capture_exception
  end

  private

  def reschedule_inactivity(pending_execution)
    due_at = pending_execution.inactivity_due_at
    return false if due_at.nil?

    pending_execution.update!(status: :pending, due_at: due_at)
    true
  end

  def skip_reason_for(pending_execution)
    return 'expired' if pending_execution.due_at < AutomationRulePendingExecution::DUE_WINDOW.ago

    structural_skip_reason(pending_execution) || behavioral_skip_reason(pending_execution)
  end

  def structural_skip_reason(pending_execution)
    rule = pending_execution.automation_rule
    return 'rule_inactive' if rule.nil? || !rule.active?
    return 'conversation_gone' if pending_execution.conversation.nil?

    nil
  end

  def behavioral_skip_reason(pending_execution)
    return 'episode_moved' unless pending_execution.episode_current?
    return 'conditions_changed' unless conditions_still_match?(pending_execution)

    nil
  end

  def conditions_still_match?(pending_execution)
    AutomationRules::ConditionsFilterService.new(
      pending_execution.automation_rule,
      pending_execution.conversation,
      { message: pending_execution.message }
    ).perform.present?
  end

  def execute(pending_execution)
    armed_for = pending_execution.due_at
    return unless start_run(pending_execution)

    # Read before the actions, never after: a note, a reopen and an unassign are all messages, and a
    # message writes last_activity_at. Read afterwards, the run would see itself as the activity that
    # restarts the count, and an inbox-only rule would act again every delay for ever. Activity that
    # lands while the actions run is not lost by reading early -- it reaches the row as activity_seen_at.
    conversation_anchor = AutomationRulePendingExecution.activity_anchor_for(pending_execution.conversation, nil)
    AutomationRules::ActionService.new(
      pending_execution.automation_rule,
      pending_execution.account,
      pending_execution.conversation
    ).perform
    settle(pending_execution, armed_for, conversation_anchor)
  end

  # Marked `executing` before the actions run: a row that dies from here on stays there, which no
  # sweep reclaims, so a message/email/webhook is never sent twice. Everything up to this point is
  # still retryable.
  #
  # It is also the last look at the clock before anything customer-facing happens, taken under the
  # same lock the arm takes. Activity that landed while this worker was deciding moved the clock and left the
  # claimed row alone, deliberately, because a live worker keeps its row -- and everything since the
  # claim has been a decision, not an action, so it is still free to be abandoned. After the actions
  # there is nothing to undo, which is why this is the last place that reading can happen.
  def start_run(pending_execution)
    pending_execution.with_lock do
      due_at = pending_execution.inactivity_due_at
      if due_at
        pending_execution.update!(status: :pending, due_at: due_at)
        next false
      end

      pending_execution.update!(status: :executing)
      true
    end
  end

  # A skip is as terminal as a run, and terminal rows are never swept again, so activity that landed
  # while this worker was deciding would be buried with the skip. An inactivity row goes terminal
  # only with nothing left on its clock, whichever way the decision went.
  def settle_skip(pending_execution, skip_reason)
    pending_execution.with_lock do
      due_at = pending_execution.inactivity_due_at
      next pending_execution.update!(status: :pending, skip_reason: nil, due_at: due_at) if due_at

      pending_execution.update!(status: :skipped, skip_reason: skip_reason)
    end
  end

  # Activity that landed while this worker held the row moved the clock and not the status. Reading
  # it here is what starts the next count from that activity instead of dropping it: an executed
  # row is never swept again. Somebody else's activity, that is: the conversation's own clock is
  # the snapshot taken before the actions ran, so what this run wrote is not read back as movement.
  def settle(pending_execution, armed_for, conversation_anchor)
    pending_execution.with_lock do
      due_at = pending_execution.inactivity_due_at(armed_for: armed_for, conversation_anchor: conversation_anchor)
      next pending_execution.update!(status: :pending, due_at: due_at) if due_at

      pending_execution.update!(status: :executed)
    end
  end
end
