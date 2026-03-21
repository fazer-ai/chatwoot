class InternalChat::MessageCreateService
  include Events::Types

  pattr_initialize [:channel!, :sender!, :params!]

  def perform
    @message = channel.messages.create!(
      account: channel.account,
      sender: sender,
      content: params[:content],
      content_type: params[:content_type] || :text,
      parent_id: params[:parent_id],
      echo_id: params[:echo_id]
    )

    process_attachments if params[:attachments].present?
    dispatch_event

    @message
  end

  private

  def process_attachments
    params[:attachments].each do |attachment|
      @message.attachments.create!(
        account: channel.account,
        file: attachment[:file],
        file_type: attachment[:file_type] || :file
      )
    end
  end

  def dispatch_event
    Rails.configuration.dispatcher.dispatch(INTERNAL_CHAT_MESSAGE_CREATED, Time.zone.now, message: @message)
  end
end
