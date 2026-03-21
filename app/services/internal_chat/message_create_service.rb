class InternalChat::MessageCreateService
  include Events::Types

  pattr_initialize [:channel!, :sender!, :params!]

  def perform
    validate_parent_message! if params[:parent_id].present?

    ActiveRecord::Base.transaction do
      @message = create_message
      process_attachments if params[:attachments].present?
    end

    post_create_hooks

    @message
  end

  private

  def create_message
    channel.messages.create!(
      account: channel.account,
      sender: sender,
      content: params[:content],
      content_type: params[:content_type] || :text,
      parent_id: params[:parent_id],
      echo_id: params[:echo_id],
      skip_content_validation: params[:attachments].present?
    )
  end

  def post_create_hooks
    dispatch_event
    process_mentions
    process_notifications
  end

  def validate_parent_message!
    raise ActiveRecord::RecordNotFound, 'Parent message not found in this channel' unless channel.messages.exists?(id: params[:parent_id])
  end

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

  def process_mentions
    return unless @message.content.present? && @message.content.match?(%r{\(mention://user/\d+/.+?\)|@all})

    InternalChat::MentionService.new(message: @message).perform
  end

  def process_notifications
    InternalChat::NotificationService.new(message: @message).perform
  end
end
