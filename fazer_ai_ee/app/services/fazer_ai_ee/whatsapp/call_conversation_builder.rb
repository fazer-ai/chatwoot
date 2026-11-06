module FazerAiEe::Whatsapp::CallConversationBuilder
  # A paired phone files one person under its LID and its number in the same inbox, and its
  # inbound messages follow the contact across both (Whatsapp::Session::Inbound::ConversationFinder),
  # so a call matched on the number alone would open a second thread beside the LID's.
  def contact_conversations
    return super unless inbox.channel.try(:session_provider?)

    inbox.conversations.where(contact_id: contact.id).order(last_activity_at: :desc)
  end
end
