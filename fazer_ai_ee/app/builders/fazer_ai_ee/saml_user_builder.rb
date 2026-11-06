module FazerAiEe::SamlUserBuilder
  private

  # The only attributes here that come from the assertion are the email and the name, so a
  # record Rails refuses is the IdP sending something unusable: a failed sign-in, which is
  # what `AuthenticationFailed` already means. Upstream returns the unsaved user instead, and
  # the callback then signs in a user that does not exist.
  def create_user
    super.tap do |user|
      raise SamlUserBuilder::AuthenticationFailed, I18n.t('auth.saml.authentication_failed') unless user.persisted?
    end
  end
end
