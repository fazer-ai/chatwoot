class InternalChat::DefaultChannelSetupService
  pattr_initialize [:account!]

  def perform
    ActiveRecord::Base.transaction do
      channel = find_or_create_default_channel
      sync_members(channel)
    end
  end

  private

  def find_or_create_default_channel
    account.internal_chat_channels.find_or_create_by!(
      name: default_channel_name,
      channel_type: :public_channel
    ) do |ch|
      ch.last_activity_at = Time.current
    end
  end

  def sync_members(channel)
    account.account_users.find_each do |account_user|
      channel.channel_members.find_or_create_by!(user_id: account_user.user_id) do |m|
        m.role = account_user.administrator? ? :admin : :member
      end
    end
  end

  def default_channel_name
    I18n.with_locale(account_locale) { I18n.t('internal_chat.default_channel_name', default: 'General') }
  end

  def account_locale
    account.locale || I18n.default_locale
  end
end
