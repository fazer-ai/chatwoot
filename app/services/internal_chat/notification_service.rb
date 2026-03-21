class InternalChat::NotificationService
  pattr_initialize [:message!]

  def perform
    channel_members_to_notify.each do |member|
      next if member.user_id == message.sender_id

      notify_member(member)
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

  def notify_member(member)
    if user_mentioned?(member.user_id)
      broadcast_notification(member.user, :internal_chat_mention)
    elsif !member.muted?
      broadcast_notification(member.user, :internal_chat_message)
    end
  end

  def broadcast_notification(user, type)
    payload = {
      notification_type: type,
      account_id: message.account_id,
      channel_id: message.internal_chat_channel_id,
      message_id: message.id,
      sender: message.sender&.push_event_data
    }
    ::ActionCableBroadcastJob.perform_later([user.pubsub_token], 'notification.created', payload)
  end
end
