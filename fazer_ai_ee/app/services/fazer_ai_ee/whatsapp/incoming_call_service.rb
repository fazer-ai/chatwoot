module FazerAiEe::Whatsapp::IncomingCallService
  private

  # The dashboard knows a conversation by its display id: the call widget routes to it and
  # looks it up in the store by it.
  def base_payload(call)
    super.merge(conversation_id: call.conversation.display_id)
  end
end
