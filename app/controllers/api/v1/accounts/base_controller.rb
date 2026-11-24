class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  include MfaEnforcementGuard
  before_action :current_account
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  before_action :check_account_mfa_enforcement, if: :authenticate_by_access_token?
  around_action :switch_locale_using_account_locale

  private

  def validate_token_api_access
    # `Current.account` is nil when this check runs before the account lookup: a
    # subclass that re-declares `before_action :current_account` makes Rails
    # de-duplicate the callback and move it to the end of the chain. Calling
    # `api_and_webhooks_enabled?` on nil raised NoMethodError, turning the 401 the
    # account lookup is about to render into a 500.
    return if Current.account.nil?
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end
end
