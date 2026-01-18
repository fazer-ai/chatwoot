# frozen_string_literal: true

# Sync subscription token with fazer.ai Hub on startup to ensure
# the latest subscription features are available immediately after deploy.
Rails.application.config.after_initialize do
  next unless Rails.env.production?

  Internal::CheckNewVersionsJob.perform_later(jitter_applied: true)
end
