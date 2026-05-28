class Api::V1::Accounts::InternalChat::MessagesController < Api::V1::Accounts::InternalChat::BaseController
  include Events::Types

  before_action :current_channel
  before_action :fetch_message, only: [:update, :destroy, :pin, :unpin, :thread]

  MESSAGES_PER_PAGE = 50

  def index
    authorize current_channel, :show?, policy_class: InternalChat::ChannelPolicy
    @messages = paginated_messages
    render json: {
      messages: @messages.map { |msg| message_response(msg) },
      meta: pagination_meta
    }
  end

  def create
    authorize current_channel, :show?, policy_class: InternalChat::ChannelPolicy
    @message = InternalChat::MessageCreateService.new(
      channel: current_channel,
      sender: Current.user,
      params: message_params
    ).perform
    render json: message_response(@message), status: :created
  end

  def update
    authorize @message, :update?, policy_class: InternalChat::MessagePolicy
    previous_content = @message.content
    @message.update!(
      content: update_params[:content],
      content_attributes: (@message.content_attributes || {}).merge('edited_at' => Time.current.iso8601, 'previous_content' => previous_content)
    )
    dispatch_message_event(INTERNAL_CHAT_MESSAGE_UPDATED, message: @message)
    render json: message_response(@message)
  end

  def destroy
    authorize @message, :destroy?, policy_class: InternalChat::MessagePolicy
    message_data = {
      id: @message.id,
      internal_chat_channel_id: @message.internal_chat_channel_id,
      account_id: @message.account_id
    }
    @message.update!(content: I18n.t('internal_chat.messages.deleted'), content_attributes: { deleted: true })
    dispatch_message_event(INTERNAL_CHAT_MESSAGE_DELETED, message_data: message_data)
    head :ok
  end

  def pin
    authorize @message, :pin?, policy_class: InternalChat::MessagePolicy
    @message.skip_content_validation = true
    @message.update!(content_attributes: (@message.content_attributes || {}).merge('pinned' => true, 'pinned_by' => Current.user.id,
                                                                                   'pinned_at' => Time.current.iso8601))
    dispatch_message_event(INTERNAL_CHAT_MESSAGE_UPDATED, message: @message)
    render json: message_response(@message)
  end

  def unpin
    authorize @message, :unpin?, policy_class: InternalChat::MessagePolicy
    @message.skip_content_validation = true
    attrs = (@message.content_attributes || {}).except('pinned', 'pinned_by', 'pinned_at')
    @message.update!(content_attributes: attrs)
    dispatch_message_event(INTERNAL_CHAT_MESSAGE_UPDATED, message: @message)
    render json: message_response(@message)
  end

  def thread
    authorize @message, :thread?, policy_class: InternalChat::MessagePolicy
    replies = @message.replies.includes(:sender, :reactions, :replies, :attachments, :poll).ordered
    render json: {
      parent: message_response(@message),
      replies: replies.map { |msg| message_response(msg) }
    }
  end

  private

  def fetch_message
    @message = current_channel.messages.find(params[:id])
  end

  def paginated_messages
    return fetch_around_messages if params[:around].present?

    messages = apply_time_filters(base_messages_scope)
    if params[:after].present?
      messages.ordered.limit(MESSAGES_PER_PAGE)
    else
      messages.ordered.last(MESSAGES_PER_PAGE)
    end
  rescue ArgumentError
    base_messages_scope.ordered.last(MESSAGES_PER_PAGE)
  end

  def fetch_around_messages
    target = current_channel.messages.find_by(id: params[:around])
    return base_messages_scope.ordered.last(MESSAGES_PER_PAGE) unless target

    half = MESSAGES_PER_PAGE / 2
    before_msgs = base_messages_scope.where('internal_chat_messages.created_at <= ?', target.created_at)
                                     .ordered.last(half)
    after_msgs = base_messages_scope.where('internal_chat_messages.created_at > ?', target.created_at)
                                    .ordered.limit(half)
    (before_msgs + after_msgs).uniq(&:id).sort_by(&:created_at)
  end

  def base_messages_scope
    current_channel.messages
                   .includes(:sender, :reactions, :replies, :attachments, :poll)
                   .where("parent_id IS NULL OR (content_attributes->>'also_send_in_channel')::boolean = true")
  end

  def apply_time_filters(messages)
    messages = messages.where('internal_chat_messages.created_at < ?', Time.zone.parse(params[:before])) if params[:before].present?
    messages = messages.where('internal_chat_messages.created_at > ?', Time.zone.parse(params[:after])) if params[:after].present?
    messages
  end

  def pagination_meta
    {
      has_more: @messages.size >= MESSAGES_PER_PAGE
    }
  end

  def message_params
    params.permit(:content, :content_type, :parent_id, :echo_id, :also_send_in_channel, attachments: [:file, :file_type])
  end

  def update_params
    params.permit(:content)
  end

  def message_response(message) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    deleted = message.content_attributes&.dig('deleted')
    response = {
      id: message.id,
      content: message.content,
      content_type: message.content_type,
      content_attributes: message.content_attributes,
      internal_chat_channel_id: message.internal_chat_channel_id,
      sender: message.sender&.push_event_data,
      parent_id: message.parent_id,
      echo_id: message.echo_id,
      replies_count: message.replies_count,
      created_at: message.created_at,
      updated_at: message.updated_at,
      reactions: message.reactions.includes(:user).map { |r| { id: r.id, emoji: r.emoji, user_id: r.user_id, user: { name: r.user&.name } } },
      attachments: deleted ? [] : message.attachments.map { |a| attachment_response(a) }
    }
    response[:poll] = poll_data(message.poll) if !deleted && message.poll?
    response
  end

  def poll_data(poll)
    return nil unless poll

    {
      id: poll.id,
      question: poll.question,
      multiple_choice: poll.multiple_choice,
      public_results: poll.public_results,
      allow_revote: poll.allow_revote,
      expires_at: poll.expires_at,
      options: poll.options.ordered.includes(votes: :user).map { |o| poll_option_data(o, poll) },
      total_votes: poll.total_votes_count
    }
  end

  def poll_option_data(option, poll)
    data = { id: option.id, text: option.text, emoji: option.emoji, votes_count: option.votes_count,
             voted: option.votes.any? { |v| v.user_id == Current.user.id } }
    data[:voters] = option.votes.map { |v| v.user.push_event_data } if poll.public_results
    data
  end

  def attachment_response(attachment)
    {
      id: attachment.id,
      file_type: attachment.file_type,
      external_url: attachment.external_url,
      extension: attachment.extension,
      file_url: attachment.file.attached? ? url_for(attachment.file) : nil
    }
  end

  def dispatch_message_event(event, data)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, **data)
  end
end
