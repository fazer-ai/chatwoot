class InternalChat::DefaultChannelSetupService
  pattr_initialize [:account!]

  def perform
    return if default_category_exists?

    ActiveRecord::Base.transaction do
      category = create_default_category
      channel = create_default_channel(category)
      add_all_agents_as_members(channel)
    end
  end

  private

  def default_category_exists?
    account.internal_chat_categories.exists?(name: default_category_name)
  end

  def create_default_category
    account.internal_chat_categories.create!(
      name: default_category_name,
      position: 0
    )
  end

  def create_default_channel(category)
    InternalChat::Channel.create!(
      account: account,
      category: category,
      name: default_channel_name,
      channel_type: :public_channel,
      last_activity_at: Time.current
    )
  end

  def add_all_agents_as_members(channel)
    account.account_users.find_each do |account_user|
      channel.channel_members.create!(
        user_id: account_user.user_id,
        role: account_user.administrator? ? :admin : :member
      )
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
