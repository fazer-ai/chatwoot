class Api::V1::Accounts::InternalChat::ChannelMembersController < Api::V1::Accounts::InternalChat::BaseController
  before_action :current_channel
  before_action :fetch_member, only: [:update, :destroy]

  def index
    authorize current_channel, :show?, policy_class: InternalChat::ChannelPolicy
    @members = current_channel.channel_members.includes(:user)
    render json: @members.map { |member| member_response(member) }
  end

  def create
    authorize current_channel, :update?, policy_class: InternalChat::ChannelPolicy
    user_ids = Array(params[:user_ids] || [params[:user_id]]).compact.map(&:to_i)
    valid_user_ids = Current.account.users.where(id: user_ids).pluck(:id)

    members = ActiveRecord::Base.transaction do
      valid_user_ids.map do |user_id|
        current_channel.channel_members.find_or_create_by!(user_id: user_id) do |m|
          m.role = params[:role] || :member
        end
      end
    end
    render json: members.map { |member| member_response(member) }, status: :ok
  end

  def update
    authorize_member_update!
    @member.update!(member_update_params)
    render json: member_response(@member)
  end

  def destroy
    authorize_member_destroy!
    @member.destroy!
    head :ok
  end

  private

  def fetch_member
    @member = current_channel.channel_members.find(params[:id])
  end

  def authorize_member_update!
    raise Pundit::NotAuthorizedError unless @member.user_id == Current.user.id || Current.account_user&.administrator?
  end

  def authorize_member_destroy!
    raise Pundit::NotAuthorizedError unless @member.user_id == Current.user.id || Current.account_user&.administrator?
  end

  def member_update_params
    params.permit(:muted, :favorited)
  end

  def member_response(member)
    {
      id: member.id,
      user_id: member.user_id,
      role: member.role,
      muted: member.muted,
      favorited: member.favorited,
      last_read_at: member.last_read_at,
      name: member.user.name,
      avatar_url: member.user.avatar_url,
      created_at: member.created_at,
      updated_at: member.updated_at
    }
  end
end
