class InternalChat::MentionService
  pattr_initialize [:message!]

  def perform
    return if message.content.blank?

    extract_mentioned_user_ids
  end

  private

  def extract_mentioned_user_ids
    user_ids = message.content.scan(%r{\(mention://user/(\d+)/(.+?)\)}).map(&:first).uniq
    team_ids = message.content.scan(%r{\(mention://team/(\d+)/(.+?)\)}).map(&:first).uniq
    user_ids += expand_team_mentions(team_ids) if team_ids.present?

    if mentions_all?
      return [] unless sender_is_admin?

      user_ids = channel_member_user_ids.map(&:to_s)
    end

    user_ids -= [message.sender_id.to_s]
    valid_user_ids(user_ids.uniq)
  end

  def expand_team_mentions(team_ids)
    message.account.teams
           .joins(:team_members)
           .where(id: team_ids)
           .pluck('team_members.user_id')
           .map(&:to_s)
  end

  def mentions_all?
    message.content.include?('@all')
  end

  def sender_is_admin?
    account_user = message.account.account_users.find_by(user_id: message.sender_id)
    account_user&.administrator? || channel_admin?
  end

  def channel_admin?
    message.channel.channel_members.exists?(user_id: message.sender_id, role: :admin)
  end

  def channel_member_user_ids
    message.channel.channel_members.pluck(:user_id)
  end

  def valid_user_ids(user_ids)
    message.account.users.where(id: user_ids).pluck(:id).map(&:to_s)
  end
end
