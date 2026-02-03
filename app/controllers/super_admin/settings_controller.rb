class SuperAdmin::SettingsController < SuperAdmin::ApplicationController
  def show; end

  def refresh
    # rubocop:disable Rails/I18nLocaleTexts
    if ENV.fetch('FRONTEND_URL', '').blank?
      redirect_to super_admin_settings_path, alert: 'FRONTEND_URL environment variable is not set. Please configure it before syncing.'
      return
    end

    Internal::CheckNewVersionsJob.perform_now(jitter_applied: true)
    redirect_to super_admin_settings_path, notice: 'Instance status refreshed'
    # rubocop:enable Rails/I18nLocaleTexts
  end
end
