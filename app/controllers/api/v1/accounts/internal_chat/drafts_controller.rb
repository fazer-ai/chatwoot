class Api::V1::Accounts::InternalChat::DraftsController < Api::V1::Accounts::InternalChat::BaseController
  before_action :current_channel, only: [:update, :destroy]

  def index
    @drafts = InternalChat::Draft.where(user: Current.user, account: Current.account).recent
    render json: @drafts.map { |draft| draft_response(draft) }
  end

  def update
    authorize current_channel, :show?, policy_class: InternalChat::ChannelPolicy

    @draft = InternalChat::Draft.find_or_initialize_by(
      user: Current.user,
      internal_chat_channel_id: current_channel.id
    )
    @draft.assign_attributes(
      account: Current.account,
      content: draft_params[:content],
      parent_id: draft_params[:parent_id]
    )
    @draft.save!

    render json: draft_response(@draft), status: :ok
  end

  def destroy
    authorize current_channel, :show?, policy_class: InternalChat::ChannelPolicy

    @draft = InternalChat::Draft.find_by!(user: Current.user, internal_chat_channel_id: current_channel.id)
    @draft.destroy!
    head :ok
  end

  private

  def draft_params
    params.permit(:content, :parent_id)
  end

  def draft_response(draft)
    {
      id: draft.id,
      content: draft.content,
      internal_chat_channel_id: draft.internal_chat_channel_id,
      parent_id: draft.parent_id,
      created_at: draft.created_at,
      updated_at: draft.updated_at
    }
  end
end
