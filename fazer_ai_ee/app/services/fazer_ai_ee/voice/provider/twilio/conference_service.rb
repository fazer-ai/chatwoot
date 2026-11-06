module FazerAiEe::Voice::Provider::Twilio::ConferenceService
  private

  # A call answered while the inbox holds assignment for being closed is answered unclaimed,
  # including when it closes between the check and the save.
  def assign_conversation!(user)
    return if call.conversation.inbox.assignment_closed?

    super
  rescue CustomExceptions::Conversation::OutsideWorkingHours
    call.conversation.restore_attributes
  end
end
