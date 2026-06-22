class Api::V1::Accounts::OauthAuthorizationController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  protected

  def scope
    ''
  end

  def state
    Current.account.to_sgid(expires_in: 15.minutes).to_s
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end

  private

  # Allow `manager` in addition to `administrator`. Reconnecting a
  # channel (Instagram, Google, TikTok, Notion) is the same kind of
  # operation as creating an inbox, which the rest of `InboxPolicy`
  # already exposes to managers (`create?`, `update?`, `destroy?`,
  # `disconnect_channel_provider?`). Without this, a clinic manager
  # sees the red "click to reconnect" banner but gets a 401 the moment
  # they click — broken UX for a role that already owns inbox setup.
  def check_authorization
    return if Current.account_user.administrator? || Current.account_user.manager?

    raise Pundit::NotAuthorizedError
  end
end
