class InternalChat::MentionService
  pattr_initialize [:message!]

  def perform
    return if message.content.blank?

    mentioned_user_ids = extract_mentioned_user_ids
    return if mentioned_user_ids.blank?

    create_mention_notifications(mentioned_user_ids)
  end

  private

  def extract_mentioned_user_ids
    user_ids = message.content.scan(%r{\(mention://user/(\d+)/(.+?)\)}).map(&:first).uniq

    if mentions_all?
      return [] unless sender_is_admin?

      user_ids = channel_member_user_ids.map(&:to_s)
    end

    user_ids -= [message.sender_id.to_s]
    valid_user_ids(user_ids)
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

  def create_mention_notifications(user_ids)
    user_ids.each do |user_id|
      user = User.find_by(id: user_id)
      next if user.blank?

      user.notifications.create!(
        notification_type: :internal_chat_mention,
        account: message.account,
        primary_actor: message.channel,
        secondary_actor: message
      )
    end
  end
end
