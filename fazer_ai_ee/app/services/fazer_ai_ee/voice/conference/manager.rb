module FazerAiEe::Voice::Conference::Manager
  private

  # A call answered while the inbox holds assignment for being closed is answered unclaimed,
  # including when it closes between the check and the save.
  def auto_assign_conversation!(user_id)
    return if call.conversation.inbox.assignment_closed?

    super
  rescue CustomExceptions::Conversation::OutsideWorkingHours
    call.conversation.restore_attributes
  end
end
