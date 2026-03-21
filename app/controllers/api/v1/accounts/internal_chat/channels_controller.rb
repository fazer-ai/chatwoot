class Api::V1::Accounts::InternalChat::ChannelsController < Api::V1::Accounts::InternalChat::BaseController # rubocop:disable Metrics/ClassLength
  include Events::Types

  before_action :current_channel, only: [:show, :update, :destroy, :archive, :unarchive, :toggle_typing_status, :mark_read, :mark_unread]

  RECENT_MESSAGES_LIMIT = 20

  def index
    authorize InternalChat::Channel, :index?
    @channels = filtered_channels
    render json: @channels.map { |channel| channel_index_response(channel) }
  end

  def show
    authorize @current_channel, :show?
    render json: channel_show_response(@current_channel)
  end

  def create
    @channel = build_channel
    authorize @channel, :create?

    ActiveRecord::Base.transaction do
      @channel.save!
      add_creator_as_admin
      add_initial_members
    end

    render json: channel_show_response(@channel), status: :ok
  end

  def update
    authorize @current_channel, :update?
    @current_channel.update!(channel_params)
    dispatch_channel_event(@current_channel)
    render json: channel_show_response(@current_channel)
  end

  def destroy
    authorize @current_channel, :destroy?
    @current_channel.destroy!
    head :ok
  end

  def archive
    authorize @current_channel, :archive?
    @current_channel.archived!
    dispatch_channel_event(@current_channel)
    render json: channel_show_response(@current_channel)
  end

  def unarchive
    authorize @current_channel, :unarchive?
    @current_channel.active!
    dispatch_channel_event(@current_channel)
    render json: channel_show_response(@current_channel)
  end

  def toggle_typing_status
    authorize @current_channel, :toggle_typing_status?
    InternalChat::TypingStatusManager.new(channel: @current_channel, user: Current.user, params: params).perform
    head :ok
  end

  def mark_read
    authorize @current_channel, :mark_read?
    membership = @current_channel.channel_members.find_by(user_id: Current.user.id)
    membership&.update!(last_read_at: Time.current)
    head :ok
  end

  def mark_unread
    authorize @current_channel, :mark_unread?
    membership = @current_channel.channel_members.find_by(user_id: Current.user.id)
    if membership.present? && params[:message_id].present?
      message = @current_channel.messages.find(params[:message_id])
      membership.update!(last_read_at: message.created_at - 1.second)
    end
    head :ok
  end

  private

  def filtered_channels
    channels = Current.account.internal_chat_channels.includes(:channel_members, :category)
    channels = apply_type_filter(channels)
    channels = apply_category_filter(channels)
    channels = apply_status_filter(channels)
    channels = apply_visibility_filter(channels)
    channels.order(last_activity_at: :desc)
  end

  def apply_type_filter(channels)
    case params[:type]
    when 'text_channels'
      channels.text_channels
    when 'direct_messages'
      channels.direct_messages
    else
      channels
    end
  end

  def apply_category_filter(channels)
    return channels if params[:category_id].blank?

    channels.where(category_id: params[:category_id])
  end

  def apply_status_filter(channels)
    case params[:status]
    when 'archived'
      channels.archived
    else
      channels.active
    end
  end

  def apply_visibility_filter(channels)
    return channels if Current.account_user&.administrator?

    channels.where(channel_type: :public_channel)
            .or(channels.where(id: Current.user.internal_chat_channels.select(:id)))
  end

  def build_channel
    if dm_params?
      find_or_build_dm
    else
      Current.account.internal_chat_channels.build(channel_params.merge(created_by: Current.user))
    end
  end

  def dm_params?
    params[:channel_type] == 'dm' || params.dig(:channel, :channel_type) == 'dm'
  end

  def find_or_build_dm
    user_ids = dm_member_ids
    existing_dm = find_existing_dm(user_ids)
    return existing_dm if existing_dm.present?

    Current.account.internal_chat_channels.build(
      channel_type: :dm,
      name: nil,
      created_by: Current.user
    )
  end

  def find_existing_dm(user_ids)
    Current.account.internal_chat_channels.where(channel_type: :dm).find_each do |ch|
      member_ids = ch.channel_members.pluck(:user_id).sort
      return ch if member_ids == user_ids.sort
    end
    nil
  end

  def dm_member_ids
    ids = Array(params[:member_ids] || params.dig(:channel, :member_ids)).map(&:to_i)
    ids << Current.user.id unless ids.include?(Current.user.id)
    ids
  end

  def add_creator_as_admin
    return if @channel.channel_type_dm?
    return if @channel.channel_members.exists?(user_id: Current.user.id)

    @channel.channel_members.create!(user_id: Current.user.id, role: :admin)
  end

  def add_initial_members
    member_ids = Array(params[:member_ids] || params.dig(:channel, :member_ids)).map(&:to_i)
    member_ids << Current.user.id if @channel.channel_type_dm? && member_ids.exclude?(Current.user.id)

    member_ids.uniq.each do |user_id|
      next if @channel.channel_members.exists?(user_id: user_id)

      @channel.channel_members.create!(user_id: user_id, role: :member)
    end
  end

  def channel_params
    params.require(:channel).permit(:name, :description, :channel_type, :category_id)
  end

  def channel_base_response(channel)
    {
      id: channel.id,
      name: channel.name,
      description: channel.description,
      channel_type: channel.channel_type,
      status: channel.status,
      category_id: channel.category_id,
      last_activity_at: channel.last_activity_at,
      created_at: channel.created_at,
      updated_at: channel.updated_at
    }
  end

  def channel_index_response(channel)
    membership = channel.channel_members.find_by(user_id: Current.user.id)
    channel_base_response(channel).merge(
      members_count: channel.channel_members.size,
      unread_count: membership&.unread_messages_count || 0
    )
  end

  def channel_show_response(channel)
    membership = channel.channel_members.find_by(user_id: Current.user.id)
    recent_messages = channel.messages.includes(:sender, :reactions).recent.limit(RECENT_MESSAGES_LIMIT).reverse
    members = channel.channel_members.includes(:user)

    channel_base_response(channel).merge(
      account_id: channel.account_id,
      created_by_id: channel.created_by_id,
      members_count: members.size,
      unread_count: membership&.unread_messages_count || 0,
      members: members.map { |m| member_response(m) },
      messages: recent_messages.map { |msg| message_response(msg) }
    )
  end

  def member_response(member)
    {
      id: member.id,
      user_id: member.user_id,
      role: member.role,
      muted: member.muted,
      favorited: member.favorited,
      name: member.user.name,
      avatar_url: member.user.avatar_url
    }
  end

  def message_response(message)
    {
      id: message.id,
      content: message.content,
      content_type: message.content_type,
      content_attributes: message.content_attributes,
      sender: message.sender&.push_event_data,
      parent_id: message.parent_id,
      echo_id: message.echo_id,
      created_at: message.created_at,
      updated_at: message.updated_at,
      reactions: message.reactions.map { |r| { id: r.id, emoji: r.emoji, user_id: r.user_id } }
    }
  end

  def dispatch_channel_event(channel)
    Rails.configuration.dispatcher.dispatch(INTERNAL_CHAT_CHANNEL_UPDATED, Time.zone.now, channel: channel)
  end
end
