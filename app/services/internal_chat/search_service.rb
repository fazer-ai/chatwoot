class InternalChat::SearchService
  CHANNELS_LIMIT = 10
  DMS_LIMIT = 10
  MESSAGES_PER_PAGE = 15

  def initialize(current_user:, current_account:, params: {})
    @current_user = current_user
    @current_account = current_account
    @query = params[:q].to_s.strip
    @page = [params[:page].to_i, 1].max
  end

  def perform
    return empty_results if @query.length < 3

    {
      channels: search_channels,
      dms: search_dms,
      messages: search_messages,
      meta: { messages_page: @page, messages_has_more: messages_has_more?, search_limited: InternalChat::Limits.search_history_days.present? }
    }
  end

  private

  def search_channels
    channels = accessible_channels.text_channels.active
    channels = channels.where(
      'f_unaccent(internal_chat_channels.name) ILIKE f_unaccent(:q) ' \
      'OR f_unaccent(internal_chat_channels.description) ILIKE f_unaccent(:q)',
      q: "%#{sanitized_query}%"
    )
    channels.limit(CHANNELS_LIMIT).select(:id, :name, :description, :channel_type).map do |ch|
      { id: ch.id, name: ch.name, description: ch.description, channel_type: ch.channel_type }
    end
  end

  def search_dms
    results = dm_search_scope.limit(DMS_LIMIT).to_a
    users_by_id = User.where(id: results.map(&:peer_user_id)).index_by(&:id)
    results.map { |ch| serialize_dm(ch, users_by_id[ch.peer_user_id]) }
  end

  def dm_search_scope
    peer_join = 'INNER JOIN internal_chat_channel_members peer_members ' \
                'ON peer_members.internal_chat_channel_id = internal_chat_channels.id'
    select_cols = 'internal_chat_channels.id, internal_chat_channels.channel_type, ' \
                  'users.id AS peer_user_id, users.name AS peer_name'

    @current_account.internal_chat_channels.direct_messages.active
                    .joins(:channel_members)
                    .where(internal_chat_channel_members: { user_id: @current_user.id, hidden: false })
                    .joins(peer_join)
                    .joins('INNER JOIN users ON users.id = peer_members.user_id')
                    .where.not(users: { id: @current_user.id })
                    .where('f_unaccent(users.name) ILIKE f_unaccent(:q)', q: "%#{sanitized_query}%")
                    .select(select_cols)
                    .distinct
  end

  def serialize_dm(channel, user)
    {
      id: channel.id,
      channel_type: channel.channel_type,
      peer: { user_id: channel.peer_user_id, name: channel.peer_name, avatar_url: user&.avatar_url }
    }
  end

  def search_messages
    not_deleted = <<~SQL.squish
      internal_chat_messages.content_attributes->>'deleted' IS NULL
      OR internal_chat_messages.content_attributes->>'deleted' != ?
    SQL

    messages = InternalChat::Message
               .where(account_id: @current_account.id)
               .where(internal_chat_channel_id: accessible_channel_ids)
               .where('f_unaccent(internal_chat_messages.content) ILIKE f_unaccent(:q)', q: "%#{sanitized_query}%")
               .where(not_deleted, 'true')
               .then { |msgs| apply_search_history_limit(msgs) }
               .includes(:sender, :channel)
               .order(created_at: :desc)
               .offset((@page - 1) * MESSAGES_PER_PAGE)
               .limit(MESSAGES_PER_PAGE + 1)

    @fetched_messages = messages.to_a
    @fetched_messages.first(MESSAGES_PER_PAGE).map { |msg| serialize_message(msg) }
  end

  def messages_has_more?
    return false unless @fetched_messages

    @fetched_messages.length > MESSAGES_PER_PAGE
  end

  def serialize_message(msg)
    {
      id: msg.id,
      content: msg.content,
      channel_id: msg.internal_chat_channel_id,
      channel_name: msg.channel&.name,
      channel_type: msg.channel&.channel_type,
      parent_id: msg.parent_id,
      created_at: msg.created_at,
      sender: msg.sender ? { id: msg.sender.id, name: msg.sender.name, avatar_url: msg.sender.avatar_url } : nil
    }
  end

  def accessible_channels
    channels = @current_account.internal_chat_channels
    user_channels = channels.where(id: @current_user.internal_chat_channels.select(:id))
    account_user = @current_account.account_users.find_by(user_id: @current_user.id)

    if account_user&.administrator?
      channels.where(channel_type: %i[public_channel private_channel]).or(user_channels)
    else
      channels.where(channel_type: :public_channel).or(user_channels)
    end
  end

  def accessible_channel_ids
    @accessible_channel_ids ||= accessible_channels.pluck(:id)
  end

  def apply_search_history_limit(messages)
    days = InternalChat::Limits.search_history_days
    return messages if days.blank?

    messages.where('internal_chat_messages.created_at >= ?', days.days.ago)
  end

  def sanitized_query
    @sanitized_query ||= ActiveRecord::Base.sanitize_sql_like(@query)
  end

  def empty_results
    { channels: [], dms: [], messages: [], meta: { messages_page: 1, messages_has_more: false } }
  end
end
