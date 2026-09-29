# Prepended on DeviseOverrides::PasswordsController, which finds the user by the token digest
# and resets the password without asking Devise whether the link is still inside
# `reset_password_within`. Devise's own `reset_password_by_token` does ask, and an expired
# link answers exactly like an unknown one (#762).
#
# An agent invitation reaches the same flow: its email links here with a token minted when it
# was sent, and the reset is what confirms the invitee. So an unconfirmed account is holding
# an invitation, which gets days rather than the hours a reset gets (#769).
#
# A module of the fork's rather than an edit to the upstream controller, so an upstream sync
# never conflicts on it; `prepend_mod_with` in that file only reaches `enterprise/`, which
# the CE image removes.
module ResetPasswordPeriodGuard
  INVITATION_WITHIN = 7.days

  def update
    digest = Devise.token_generator.digest(self, :reset_password_token, params[:reset_password_token])
    recoverable = User.find_by(reset_password_token: digest)
    # One transaction, because the reset confirms the account before it validates the new
    # password: a password the server rejects would otherwise leave an invitee confirmed, and
    # the retry with the same invitation would fall into the 6-hour window.
    return ActiveRecord::Base.transaction { super } if recoverable.nil? || reset_token_in_period?(recoverable)

    render json: { message: 'Invalid token', redirect_url: '/' }, status: :unprocessable_entity
  end

  private

  def reset_token_in_period?(user)
    return user.reset_password_period_valid? if user.confirmed?

    user.reset_password_sent_at.present? && user.reset_password_sent_at.utc >= INVITATION_WITHIN.ago.utc
  end
end
