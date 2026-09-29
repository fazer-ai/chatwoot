# frozen_string_literal: true

Rails.application.config.to_prepare do
  DeviseOverrides::PasswordsController.prepend(ResetPasswordPeriodGuard)
end
