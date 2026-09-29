# Prepended on DeviseOverrides::PasswordsController, which finds the user by the token digest
# and resets the password without asking Devise whether the link is still inside
# `reset_password_within`. Devise's own `reset_password_by_token` does ask, and an expired
# link answers exactly like an unknown one (#762).
#
# A module of the fork's rather than an edit to the upstream controller, so an upstream sync
# never conflicts on it; `prepend_mod_with` in that file only reaches `enterprise/`, which
# the CE image removes.
module ResetPasswordPeriodGuard
  def update
    digest = Devise.token_generator.digest(self, :reset_password_token, params[:reset_password_token])
    recoverable = User.find_by(reset_password_token: digest)
    return super if recoverable.nil? || recoverable.reset_password_period_valid?

    render json: { message: 'Invalid token', redirect_url: '/' }, status: :unprocessable_entity
  end
end
