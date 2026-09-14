class ConversationBuilder
  pattr_initialize [:params!, :contact_inbox!]

  def perform
    look_up_exising_conversation || create_new_conversation
  end

  private

  def look_up_exising_conversation
    return unless @contact_inbox.inbox.lock_to_single_conversation?

    @contact_inbox.inbox.conversations.where(contact_id: @contact_inbox.contact_id).last
  end

  def create_new_conversation
    ::Conversation.create!(conversation_params)
  end

  # An inbox with an active bot starts its conversations pending, and that default is the bot's
  # turn to speak first. A caller that sends `status` is creating the conversation on purpose and
  # has said otherwise, so the model is told the status was asked for rather than defaulted: the
  # column's own default is `open`, so nothing about the value itself separates the two.
  def requested_status
    return {} if params[:status].blank?

    status = params[:status].to_s
    unless ::Conversation.statuses.key?(status)
      raise CustomExceptions::Conversation::InvalidStatus.new(status: status, statuses: ::Conversation.statuses.keys)
    end

    { status: status, status_requested_by_caller: true }
  end

  def conversation_params
    additional_attributes = params[:additional_attributes]&.permit! || {}
    custom_attributes = params[:custom_attributes]&.permit! || {}

    {
      account_id: @contact_inbox.inbox.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      snoozed_until: params[:snoozed_until],
      assignee_id: params[:assignee_id],
      team_id: params[:team_id]
    }.merge(requested_status)
  end
end
