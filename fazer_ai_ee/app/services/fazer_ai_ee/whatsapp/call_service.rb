module FazerAiEe::Whatsapp::CallService
  # A string, the SDP itself: anything else would be taken as an answer and fail later.
  def accept
    raise Voice::CallErrors::CallFailed, 'sdp_answer is required' unless sdp_answer.is_a?(String) && sdp_answer.present?

    super
  end

  # The connector can report a pickup, or an end, before the call it is about was recorded,
  # and the call stays ringing here until they are applied: an agent hanging up before then
  # would end as unanswered a call that was answered, or one that had ended. Applied under
  # the same lock upstream's terminate takes, so nothing lands between the two.
  def terminate
    call.with_lock do
      apply_kept_connector_outcomes unless call.terminal?
      super
    end
  end

  private

  def apply_kept_connector_outcomes
    return unless call.inbox.channel.session_provider?

    Whatsapp::ConnectorCallService.new(inbox: call.inbox).apply_kept_outcomes(call)
  end

  # Meta has already accepted by now, so an inbox holding assignment while closed is answered
  # unclaimed, including when it closes between the check and the save.
  def claim_conversation_and_set_call_status
    return update_conversation_call_status(call.display_status) if call.conversation.inbox.assignment_closed?

    super
  rescue CustomExceptions::Conversation::OutsideWorkingHours
    call.conversation.restore_attributes
    update_conversation_call_status(call.display_status)
  end
end
