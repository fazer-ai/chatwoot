class SuperAdmin::Integrations::ClickupController < SuperAdmin::ApplicationController
  # Manually kicks off `Integrations::Clickup::RegisterWebhookJob` from the
  # Super Admin → ClickUp screen. The job is already wired to run on the
  # `after_commit` of CLICKUP_API_KEY (see `config/initializers/
  # clickup_webhook_hook.rb`), but that hook only fires on saves — if the
  # key was seeded before the hook shipped, or if the previous ClickUp API
  # call failed silently, the admin has no way to retry from the UI.
  # This action closes that loop.
  EMPTY_RESPONSE_ALERT = 'A chamada ao ClickUp não retornou um webhook. Confira os logs do Sidekiq.'.freeze

  def register_webhook
    Integrations::Clickup::RegisterWebhookJob.perform_now

    webhook_id = InstallationConfig.find_by(name: 'CLICKUP_WEBHOOK_ID')&.value.presence
    if webhook_id.present?
      redirect_to super_admin_app_config_path(config: 'clickup'),
                  flash: { success: "Webhook registrado no ClickUp. ID: #{webhook_id}" }
    else
      redirect_to super_admin_app_config_path(config: 'clickup'), alert: EMPTY_RESPONSE_ALERT
    end
  rescue Integrations::Clickup::Client::Unauthorized => e
    redirect_to super_admin_app_config_path(config: 'clickup'),
                alert: "Credencial do ClickUp inválida: #{e.message}"
  rescue Integrations::Clickup::Client::Error, StandardError => e
    redirect_to super_admin_app_config_path(config: 'clickup'),
                alert: "Não foi possível registrar o webhook: #{e.message}"
  end
end
