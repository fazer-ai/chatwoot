class Api::V1::Accounts::InternalChat::PollsController < Api::V1::Accounts::InternalChat::BaseController
  include Events::Types

  before_action :set_poll, only: [:vote]
  before_action :set_poll_for_unvote, only: [:unvote]

  def create
    return render_pro_required('polls') unless InternalChat::Limits.polls_enabled?

    @channel = Current.account.internal_chat_channels.find(params[:channel_id])
    authorize @channel, :show?, policy_class: InternalChat::ChannelPolicy
    raise ActionController::BadRequest, 'Options are required' if poll_params[:options].blank?

    ActiveRecord::Base.transaction do
      @message = create_poll_message
      @poll = build_poll
      create_poll_options
    end

    dispatch_message_created_event

    render json: message_with_poll_response(@message, @poll), status: :created
  end

  def vote
    ActiveRecord::Base.transaction do
      validate_vote!
      @vote = @option.votes.create!(user: Current.user)
    end
    dispatch_poll_event

    render json: message_with_poll_response(@poll.message, @poll.reload), status: :ok
  end

  def unvote
    raise ActionController::BadRequest, 'Poll has expired' if @poll.expired?

    @vote = if params[:option_id].present?
              option = @poll.options.find(params[:option_id])
              option.votes.find_by!(user_id: Current.user.id)
            else
              InternalChat::PollVote.joins(:option)
                                    .where(internal_chat_poll_options: { internal_chat_poll_id: @poll.id }, user_id: Current.user.id)
                                    .first!
            end
    @vote.destroy!
    dispatch_poll_event

    render json: message_with_poll_response(@poll.message, @poll.reload), status: :ok
  end

  private

  def set_poll
    @poll = InternalChat::Poll.joins(:message).where(internal_chat_messages: { account_id: Current.account.id }).find(params[:id])
    @option = @poll.options.find(params[:option_id])
    channel = @poll.message.channel
    authorize channel, :show?, policy_class: InternalChat::ChannelPolicy
  end

  def set_poll_for_unvote
    @poll = InternalChat::Poll.joins(:message).where(internal_chat_messages: { account_id: Current.account.id }).find(params[:id])
    channel = @poll.message.channel
    authorize channel, :show?, policy_class: InternalChat::ChannelPolicy
  end

  def create_poll_message
    @channel.messages.create!(
      account: Current.account,
      sender: Current.user,
      content: poll_params[:question],
      content_type: :poll
    )
  end

  def build_poll
    @message.create_poll!(
      question: poll_params[:question],
      multiple_choice: poll_params[:multiple_choice] || false,
      public_results: poll_params.fetch(:public_results, true),
      allow_revote: poll_params.fetch(:allow_revote, true),
      expires_at: poll_params[:expires_at]
    )
  end

  def validate_vote!
    raise ActionController::BadRequest, 'Poll has expired' if @poll.expired?

    existing_votes = existing_user_votes
    return unless existing_votes.exists?

    raise ActionController::BadRequest, 'Revoting is not allowed' unless @poll.allow_revote

    if @poll.multiple_choice
      raise ActionController::BadRequest, 'Already voted for this option' if @option.votes.exists?(user_id: Current.user.id)
    else
      existing_votes.destroy_all
    end
  end

  def existing_user_votes
    InternalChat::PollVote.joins(:option).where(
      internal_chat_poll_options: { internal_chat_poll_id: @poll.id },
      user_id: Current.user.id
    )
  end

  def create_poll_options
    poll_params[:options].each_with_index do |option_attrs, index|
      @poll.options.create!(
        text: option_attrs[:text],
        emoji: option_attrs[:emoji],
        image_url: option_attrs[:image_url],
        position: index
      )
    end
  end

  def poll_params
    params.permit(:question, :multiple_choice, :public_results, :allow_revote, :expires_at, :channel_id,
                  options: [:text, :emoji, :image_url])
  end

  def message_with_poll_response(message, poll)
    {
      id: message.id,
      content: message.content,
      content_type: message.content_type,
      content_attributes: (message.content_attributes || {}).merge(poll: poll_response(poll)),
      internal_chat_channel_id: message.internal_chat_channel_id,
      sender: message.sender.push_event_data,
      parent_id: message.parent_id,
      created_at: message.created_at,
      updated_at: message.updated_at,
      attachments: [],
      reactions: []
    }
  end

  def poll_response(poll)
    {
      id: poll.id,
      question: poll.question,
      multiple_choice: poll.multiple_choice,
      public_results: poll.public_results,
      allow_revote: poll.allow_revote,
      expires_at: poll.expires_at,
      internal_chat_message_id: poll.internal_chat_message_id,
      options: poll.options.ordered.includes(votes: :user).map { |option| option_response(option, poll) },
      total_votes: poll.total_votes_count,
      created_at: poll.created_at,
      updated_at: poll.updated_at
    }
  end

  def option_response(option, poll)
    response = {
      id: option.id,
      text: option.text,
      emoji: option.emoji,
      image_url: option.image_url,
      position: option.position,
      votes_count: option.votes_count,
      voted: option.votes.any? { |v| v.user_id == Current.user.id }
    }
    response[:voters] = option.votes.map { |v| v.user.push_event_data } if poll.public_results
    response
  end

  def dispatch_message_created_event
    Rails.configuration.dispatcher.dispatch(INTERNAL_CHAT_MESSAGE_CREATED, Time.zone.now, message: @message)
  end

  def dispatch_poll_event
    Rails.configuration.dispatcher.dispatch(INTERNAL_CHAT_POLL_VOTED, Time.zone.now, poll: @poll, message: @poll.message)
  end
end
