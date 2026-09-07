# frozen_string_literal: true

# Devise::Mailer inherits from ApplicationMailer (config.parent_mailer), so it would otherwise
# pick up the brand of whatever account is in Current -- and User#send_devise_notification
# falls back to `accounts.first` when there is none, which for a user in several workspaces is
# whichever row the database returns. A password reset is a credential of the person on this
# installation, not of one of their workspaces, so it stays on the installation's brand.
Rails.application.config.to_prepare do
  Devise::Mailer.installation_branded!
end
