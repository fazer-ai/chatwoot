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
      content_attributes: build_content_attributes,
      skip_content_validation: params[:attachments].present?
    )
  end

  def build_content_attributes
    return {} unless params[:parent_id].present? && ActiveModel::Type::Boolean.new.cast(params[:also_send_in_channel])

    { 'also_send_in_channel' => true }
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
        file_type: detect_file_type(attachment)
      )
    end
  end

  def detect_file_type(attachment)
    return attachment[:file_type].to_sym if attachment[:file_type].present?

    content_type = attachment[:file]&.content_type || ''
    return :image if content_type.start_with?('image/')
    return :audio if content_type.start_with?('audio/')
    return :video if content_type.start_with?('video/')

    :file
  end

  def dispatch_event
    Rails.configuration.dispatcher.dispatch(INTERNAL_CHAT_MESSAGE_CREATED, Time.zone.now, message: @message)
  end

  def process_mentions
    return unless @message.content.present? && @message.content.match?(%r{\(mention://(user|team)/\d+/.+?\)|@all})

    mentioned_ids = InternalChat::MentionService.new(message: @message).perform
    return if mentioned_ids.blank?

    @message.update!(content_attributes: @message.content_attributes.merge('mentioned_user_ids' => mentioned_ids.map(&:to_i)))
  end

  def process_notifications
    InternalChat::NotificationService.new(message: @message).perform
  end
end
