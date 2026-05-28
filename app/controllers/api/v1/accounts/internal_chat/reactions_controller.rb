class Api::V1::Accounts::InternalChat::ReactionsController < Api::V1::Accounts::InternalChat::BaseController
  include Events::Types

  before_action :fetch_message

  def create
    @reaction = @message.reactions.build(user: Current.user, emoji: reaction_params[:emoji])
    authorize @reaction, :create?, policy_class: InternalChat::ReactionPolicy
    @reaction.save!
    dispatch_reaction_event(INTERNAL_CHAT_REACTION_CREATED, reaction: @reaction)
    render json: reaction_response(@reaction), status: :created
  end

  def destroy
    @reaction = @message.reactions.find(params[:id])
    authorize @reaction, :destroy?, policy_class: InternalChat::ReactionPolicy
    reaction_data = {
      id: @reaction.id,
      message_id: @reaction.internal_chat_message_id,
      internal_chat_channel_id: @message.internal_chat_channel_id,
      account_id: @message.account_id,
      user_id: @reaction.user_id,
      emoji: @reaction.emoji
    }
    @reaction.destroy!
    dispatch_reaction_event(INTERNAL_CHAT_REACTION_DELETED, reaction_data: reaction_data)
    head :ok
  end

  private

  def fetch_message
    @message = InternalChat::Message.joins(:channel).where(internal_chat_channels: { account_id: Current.account.id }).find(params[:message_id])
  end

  def reaction_response(reaction)
    {
      id: reaction.id,
      emoji: reaction.emoji,
      user_id: reaction.user_id,
      user: { name: reaction.user&.name },
      internal_chat_message_id: reaction.internal_chat_message_id,
      created_at: reaction.created_at
    }
  end

  def reaction_params
    params.permit(:emoji)
  end

  def dispatch_reaction_event(event, **data)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, **data)
  end
end
