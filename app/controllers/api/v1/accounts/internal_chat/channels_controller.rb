class Api::V1::Accounts::InternalChat::ChannelsController < Api::V1::Accounts::InternalChat::BaseController # rubocop:disable Metrics/ClassLength
  include Events::Types

  before_action :current_channel, only: [:show, :update, :destroy, :archive, :unarchive, :toggle_typing_status, :mark_read, :mark_unread]

  RECENT_MESSAGES_LIMIT = 20
  # Arbitrary 32-bit namespace for the private-channel limit advisory lock; paired with account id.
  PRIVATE_CHANNEL_LOCK_KEY = 0x49434C4D # 'ICLM'

  def index
    authorize InternalChat::Channel, :index?
    @channels = filtered_channels
    @unread_counts = compute_unread_counts(@channels)
    @mention_channel_ids = compute_mention_channel_ids(@channels)
    render json: @channels.map { |channel| channel_index_response(channel) }
  end

  def show
    authorize @current_channel, :show?
    render json: channel_show_response(@current_channel)
  end

  def create
    @channel = build_channel
    authorize @channel, :create?
    created = @channel.new_record?

    if dm_params? && created
      create_dm_with_lock
    else
      with_private_channel_limit_lock(@channel) do
        return if enforce_private_channel_limit(@channel)

        ActiveRecord::Base.transaction do
          @channel.save!
          add_creator_as_admin
          add_initial_members
          add_channel_type_members
        end
      end
    end

    dispatch_channel_event(@channel) if created
    render json: channel_show_response(@channel), status: :created
  end

  def update
    authorize @current_channel, :update?
    attrs = update_channel_params
    validate_category!(attrs[:category_id])
    @current_channel.update!(attrs)
    dispatch_channel_event(@current_channel)
    render json: channel_show_response(@current_channel)
  end

  def destroy
    authorize @current_channel, :destroy?
    # Capture member tokens before destroying so the listener can broadcast to them
    cached_tokens = channel_member_tokens(@current_channel)
    @current_channel.destroy!
    Rails.configuration.dispatcher.dispatch(INTERNAL_CHAT_CHANNEL_UPDATED, Time.zone.now, channel: @current_channel,
                                                                                          member_tokens: cached_tokens)
    head :ok
  end

  def archive
    authorize @current_channel, :archive?
    head(:unprocessable_entity) and return if @current_channel.channel_type_dm?

    @current_channel.archived!
    dispatch_channel_event(@current_channel)
    render json: channel_show_response(@current_channel)
  end

  def unarchive
    authorize @current_channel, :unarchive?

    with_private_channel_limit_lock(@current_channel) do
      return if enforce_private_channel_limit(@current_channel)

      @current_channel.active!
    end

    dispatch_channel_event(@current_channel)
    render json: channel_show_response(@current_channel)
  end

  def toggle_typing_status
    authorize @current_channel, :toggle_typing_status?
    InternalChat::TypingStatusManager.new(
      channel: @current_channel, user: Current.user, params: { typing_status: typing_status_param }
    ).perform
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
    msg_id = mark_unread_params[:message_id]
    return head(:ok) if msg_id.blank?

    membership = @current_channel.channel_members.find_by!(user_id: Current.user.id)
    message = @current_channel.messages.find(msg_id)
    membership.update!(last_read_at: message.created_at - 1.second)
    head :ok
  end

  private

  def enforce_private_channel_limit(channel)
    return unless channel.channel_type_private_channel?

    max = InternalChat::Limits.max_private_channels
    return if max.blank?

    count = Current.account.internal_chat_channels.where(channel_type: :private_channel).active.count
    render_pro_required('private_channels') if count >= max
  end

  # Postgres advisory transaction lock keyed by account so concurrent create/unarchive
  # cannot bypass the private-channel limit by racing between count and save.
  def with_private_channel_limit_lock(channel)
    return yield unless channel.channel_type_private_channel? && InternalChat::Limits.max_private_channels.present?

    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?, ?)', PRIVATE_CHANNEL_LOCK_KEY, Current.account.id])
      )
      yield
    end
  end

  def filtered_channels
    channels = Current.account.internal_chat_channels.includes(channel_members: { user: :account_users }, category: [])
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
    user_channels = channels.where(id: Current.user.internal_chat_channels.select(:id))

    return channels.where(channel_type: %i[public_channel private_channel]).or(user_channels) if Current.account_user&.administrator?

    channels.where(channel_type: :public_channel).or(user_channels)
  end

  def build_channel
    if dm_params?
      find_or_build_dm
    else
      attrs = create_channel_params.except(:member_ids, :team_ids)
      validate_category!(attrs[:category_id])
      Current.account.internal_chat_channels.build(attrs.merge(created_by: Current.user))
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
    sorted_ids = user_ids.sort
    member_count = sorted_ids.size

    Current.account.internal_chat_channels
           .where(channel_type: :dm)
           .joins(:channel_members)
           .group('internal_chat_channels.id')
           .having('COUNT(internal_chat_channel_members.id) = ?', member_count)
           .having(
             'ARRAY_AGG(internal_chat_channel_members.user_id ORDER BY internal_chat_channel_members.user_id) = ARRAY[?]::bigint[]',
             sorted_ids
           )
           .first
  end

  def dm_member_ids
    ids = Array(permitted_member_ids).map(&:to_i)
    ids = Current.account.users.where(id: ids).pluck(:id)
    ids << Current.user.id unless ids.include?(Current.user.id)
    ids
  end

  def add_creator_as_admin
    return if @channel.channel_type_dm?
    return if @channel.channel_members.exists?(user_id: Current.user.id)

    @channel.channel_members.create!(user_id: Current.user.id, role: :admin)
  end

  def add_initial_members
    member_ids = Array(permitted_member_ids).map(&:to_i)
    member_ids = Current.account.users.where(id: member_ids).pluck(:id)
    member_ids << Current.user.id if @channel.channel_type_dm? && member_ids.exclude?(Current.user.id)

    member_ids.uniq.each do |user_id|
      next if @channel.channel_members.exists?(user_id: user_id)

      @channel.channel_members.create!(user_id: user_id, role: :member)
    end
  end

  def add_channel_type_members
    return if @channel.channel_type_dm?

    if @channel.channel_type_public_channel?
      add_all_agents_as_members
    else
      add_team_members
    end
  end

  def add_all_agents_as_members
    agent_ids = Current.account.agents.where.not(id: Current.user.id).pluck(:id)
    agent_ids.each do |uid|
      @channel.channel_members.find_or_create_by!(user_id: uid) { |m| m.role = :member }
    end
  end

  def add_team_members
    team_ids = permitted_team_ids
    return if team_ids.blank?

    team_ids.each do |team_id|
      team = Current.account.teams.find_by(id: team_id)
      next unless team

      @channel.channel_teams.find_or_create_by!(team: team)
      team.members.each do |user|
        @channel.channel_members.find_or_create_by!(user_id: user.id) { |m| m.role = :member }
      end
    end
  end

  def create_channel_params
    @create_channel_params ||= params.require(:channel).permit(:name, :description, :channel_type, :category_id, member_ids: [], team_ids: [])
  end

  def update_channel_params
    params.require(:channel).permit(:name, :description, :category_id)
  end

  def permitted_member_ids
    params.permit(member_ids: [])[:member_ids] || create_channel_params[:member_ids]
  end

  def permitted_team_ids
    ids = params.permit(team_ids: [])[:team_ids] || create_channel_params[:team_ids]
    Array(ids).map(&:to_i).compact_blank
  end

  def mark_unread_params
    params.permit(:message_id)
  end

  def typing_status_param
    params.permit(:typing_status)[:typing_status]
  end

  def create_dm_with_lock
    lock_key = "internal_chat_dm_#{Current.account.id}_#{dm_member_ids.sort.join('_')}"
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?)', Zlib.crc32(lock_key)])
      )
      existing = find_existing_dm(dm_member_ids)
      if existing
        @channel = existing
      else
        @channel.save!
        add_initial_members
      end
    end
  end

  def compute_mention_channel_ids(channels)
    user_id = Current.user.id
    InternalChat::ChannelMember
      .joins(
        'INNER JOIN internal_chat_messages ' \
        'ON internal_chat_messages.internal_chat_channel_id = internal_chat_channel_members.internal_chat_channel_id ' \
        'AND internal_chat_messages.created_at > internal_chat_channel_members.last_read_at'
      )
      .where(internal_chat_channel_id: channels.select(:id), user_id: user_id)
      .where.not(last_read_at: nil)
      .where.not('internal_chat_messages.sender_id' => user_id)
      .where("internal_chat_messages.content_attributes->'mentioned_user_ids' @> ?", [user_id].to_json)
      .pluck(Arel.sql('DISTINCT internal_chat_channel_members.internal_chat_channel_id'))
  end

  def compute_unread_counts(channels)
    InternalChat::ChannelMember
      .joins(
        'INNER JOIN internal_chat_messages ' \
        'ON internal_chat_messages.internal_chat_channel_id = internal_chat_channel_members.internal_chat_channel_id ' \
        'AND internal_chat_messages.created_at > internal_chat_channel_members.last_read_at'
      )
      .where(internal_chat_channel_id: channels.select(:id), user_id: Current.user.id)
      .where.not(last_read_at: nil)
      .where.not('internal_chat_messages.sender_id' => Current.user.id)
      .group('internal_chat_channel_members.internal_chat_channel_id')
      .count('internal_chat_messages.id')
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

  def channel_index_response(channel) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    membership = channel.channel_members.detect { |member| member.user_id == Current.user.id }
    response = channel_base_response(channel).merge(
      is_dm: channel.channel_type_dm?,
      muted: membership&.muted || false,
      favorited: membership&.favorited || false,
      hidden: membership&.hidden || false,
      members_count: channel.channel_members.size,
      unread_count: @unread_counts&.dig(channel.id) || 0,
      has_unread_mention: @mention_channel_ids&.include?(channel.id) || false
    )
    if channel.channel_type_dm?
      response[:members] = channel.channel_members.map do |m|
        { user_id: m.user_id, name: m.user.name, avatar_url: m.user.avatar_url, availability_status: m.user.availability_status }
      end
    end
    response
  end

  def channel_show_response(channel) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    members = channel.channel_members.includes(:user).load
    membership = members.detect { |member| member.user_id == Current.user.id }
    recent_messages = channel.messages
                             .includes(:sender, :reactions, :replies, { poll: { options: { votes: :user } } },
                                       attachments: { file_attachment: :blob })
                             .recent.limit(RECENT_MESSAGES_LIMIT).reverse

    channel_base_response(channel).merge(
      is_dm: channel.channel_type_dm?,
      muted: membership&.muted || false,
      favorited: membership&.favorited || false,
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
    deleted = message.content_attributes&.dig('deleted')
    attrs = message.content_attributes || {}
    attrs = attrs.merge(poll: poll_response_for(message.poll)) if message.poll.present?
    {
      id: message.id,
      content: message.content,
      content_type: message.content_type,
      content_attributes: attrs,
      sender: message.sender&.push_event_data,
      parent_id: message.parent_id,
      echo_id: message.echo_id,
      replies_count: message.replies_count,
      created_at: message.created_at,
      updated_at: message.updated_at,
      reactions: reaction_responses(message),
      attachments: deleted ? [] : message.attachments.map { |a| attachment_response(a) }
    }
  end

  def poll_response_for(poll)
    {
      id: poll.id,
      question: poll.question,
      multiple_choice: poll.multiple_choice,
      public_results: poll.public_results,
      allow_revote: poll.allow_revote,
      expires_at: poll.expires_at,
      internal_chat_message_id: poll.internal_chat_message_id,
      options: poll.options.ordered.includes(votes: :user).map { |opt| poll_option_response(opt, poll) },
      total_votes: poll.total_votes_count,
      created_at: poll.created_at,
      updated_at: poll.updated_at
    }
  end

  def poll_option_response(option, poll)
    response = {
      id: option.id,
      text: option.text,
      votes_count: option.votes_count,
      voted: option.votes.any? { |v| v.user_id == Current.user.id }
    }
    response[:voters] = option.votes.map { |v| { id: v.user_id, name: v.user.name } } if poll.public_results
    response
  end

  def reaction_responses(message)
    message.reactions.includes(:user).map do |r|
      { id: r.id, emoji: r.emoji, user_id: r.user_id, user: { name: r.user&.name } }
    end
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

  def channel_member_tokens(channel)
    users = channel.channel_type_public_channel? ? channel.account.users : channel.members
    users.pluck(:pubsub_token)
  end

  def validate_category!(category_id)
    return if category_id.blank?

    Current.account.internal_chat_categories.find(category_id)
  end

  def dispatch_channel_event(channel)
    Rails.configuration.dispatcher.dispatch(INTERNAL_CHAT_CHANNEL_UPDATED, Time.zone.now, channel: channel)
  end
end
