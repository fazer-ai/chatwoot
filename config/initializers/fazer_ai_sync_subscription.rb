# frozen_string_literal: true

# Sync subscription token with fazer.ai Hub on startup to ensure
# the latest subscription features are available immediately after deploy.
Rails.application.config.after_initialize do
  next unless Rails.env.production?
  next if defined?(Rake.application) && Rake.application.top_level_tasks.any? { |task| task.start_with?('assets:') }

  Internal::CheckNewVersionsJob.perform_later(jitter_applied: true)
end
