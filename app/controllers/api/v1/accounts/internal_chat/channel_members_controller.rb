class Api::V1::Accounts::InternalChat::ChannelMembersController < Api::V1::Accounts::InternalChat::BaseController
  include Events::Types

  before_action :current_channel
  before_action :fetch_member, only: [:update, :destroy]

  def index
    authorize current_channel, :show?, policy_class: InternalChat::ChannelPolicy
    @members = current_channel.channel_members.includes(user: :account_users)
    render json: @members.map { |member| member_response(member) }
  end

  def create
    authorize current_channel, :update?, policy_class: InternalChat::ChannelPolicy
    members = create_channel_members(validated_user_ids, requested_role)
    dispatch_member_update
    render json: members.map { |member| member_response(member) }, status: :created
  end

  def update
    authorize_member_update!
    @member.update!(member_update_params)
    render json: member_response(@member)
  end

  def destroy
    authorize_member_destroy!
    removed_user = @member.user
    @member.destroy!
    dispatch_member_update(removed_user: removed_user)
    head :ok
  end

  private

  def validated_user_ids
    user_ids = Array(params[:user_ids] || [params[:user_id]]).compact.map(&:to_i)
    valid_user_ids = Current.account.users.where(id: user_ids).pluck(:id)
    raise ActionController::BadRequest, 'No valid user IDs provided' if valid_user_ids.empty?

    valid_user_ids
  end

  def create_channel_members(user_ids, role)
    ActiveRecord::Base.transaction do
      user_ids.map do |user_id|
        current_channel.channel_members.find_or_create_by!(user_id: user_id) do |m|
          m.role = role
        end
      end
    end
  end

  # Only account administrators can promote a new member to channel admin via params.
  # Channel admins (without account-admin) always create plain members.
  def requested_role
    return :member unless Current.account_user&.administrator?
    return :member if params[:role].blank?

    InternalChat::ChannelMember.roles.key?(params[:role].to_s) ? params[:role] : :member
  end

  def fetch_member
    @member = current_channel.channel_members.find(params[:id])
  end

  def authorize_member_update!
    raise Pundit::NotAuthorizedError unless @member.user_id == Current.user.id || Current.account_user&.administrator?
  end

  def authorize_member_destroy!
    raise Pundit::NotAuthorizedError unless @member.user_id == Current.user.id || Current.account_user&.administrator?
  end

  def dispatch_member_update(removed_user: nil)
    # Capture tokens before the broadcast so the removed user also receives the event
    tokens = current_channel.members.pluck(:pubsub_token)
    tokens << removed_user.pubsub_token if removed_user.present?

    Rails.configuration.dispatcher.dispatch(
      INTERNAL_CHAT_CHANNEL_UPDATED,
      Time.zone.now,
      channel: current_channel,
      member_tokens: tokens.uniq
    )
  end

  def member_update_params
    params.permit(:muted, :favorited, :hidden)
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
      availability_status: member.user.availability_status,
      created_at: member.created_at,
      updated_at: member.updated_at
    }
  end
end
