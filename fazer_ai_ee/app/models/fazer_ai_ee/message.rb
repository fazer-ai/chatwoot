module FazerAiEe::Message
  private

  # A reaction is not a reply: a human reacting to a pending conversation leaves it with Captain.
  def mark_pending_conversation_as_open_for_human_response
    return if reaction?

    super
  end
end
