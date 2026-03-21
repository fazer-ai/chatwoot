class InternalChat::DefaultChannelSetupService
  pattr_initialize [:account!]

  def perform
    ActiveRecord::Base.transaction do
      category = find_or_create_default_category
      channel = find_or_create_default_channel(category)
      sync_members(channel)
    end
  end

  private

  def find_or_create_default_category
    account.internal_chat_categories.find_or_create_by!(name: default_category_name) do |cat|
      cat.position = 0
    end
  end

  def find_or_create_default_channel(category)
    category.channels.find_or_create_by!(
      account: account,
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

  def default_category_name
    I18n.with_locale(account_locale) { I18n.t('internal_chat.default_category_name', default: 'Channels') }
  end

  def default_channel_name
    I18n.with_locale(account_locale) { I18n.t('internal_chat.default_channel_name', default: 'General') }
  end

  def account_locale
    account.locale || I18n.default_locale
  end
end
