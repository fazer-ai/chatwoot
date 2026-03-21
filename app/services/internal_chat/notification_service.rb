class InternalChat::NotificationService
  pattr_initialize [:message!]

  def perform
    channel_members_to_notify.each do |member|
      next if member.user_id == message.sender_id

      create_notification(member)
    end
  end

  private

  def channel_members_to_notify
    message.channel.channel_members.includes(:user)
  end

  def mentioned_user_ids
    @mentioned_user_ids ||= if message.content.present?
                              message.content.scan(%r{\(mention://user/(\d+)/(.+?)\)}).map(&:first).uniq.map(&:to_i)
                            else
                              []
                            end
  end

  def user_mentioned?(user_id)
    mentioned_user_ids.include?(user_id) || (message.content&.include?('@all') && sender_is_admin?)
  end

  def sender_is_admin?
    account_user = message.account.account_users.find_by(user_id: message.sender_id)
    account_user&.administrator? || message.channel.channel_members.exists?(user_id: message.sender_id, role: :admin)
  end

  def create_notification(member)
    if user_mentioned?(member.user_id)
      create_mention_notification(member.user)
    elsif !member.muted?
      create_message_notification(member.user)
    end
  end

  def create_mention_notification(user)
    user.notifications.create!(
      notification_type: :internal_chat_mention,
      account: message.account,
      primary_actor: message.channel,
      secondary_actor: message
    )
  end

  def create_message_notification(user)
    user.notifications.create!(
      notification_type: :internal_chat_message,
      account: message.account,
      primary_actor: message.channel,
      secondary_actor: message
    )
  end
end
