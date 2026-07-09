# Whenever the CLICKUP_API_KEY installation config value changes, kick off
# the RegisterWebhookJob so the ClickUp side gets a fresh webhook pointed at
# our current FRONTEND_URL. The job is idempotent — it deletes any previous
# registration before creating the new one — so re-saves are safe.
#
# Kept as a Rails.application.config.after_initialize block so it survives
# reload! in dev + does not fire during test unless an actual save happens.
Rails.application.config.after_initialize do
  InstallationConfig.class_eval do
    after_commit :maybe_register_clickup_webhook, on: [:create, :update]

    private

    def maybe_register_clickup_webhook
      return unless name == 'CLICKUP_API_KEY'
      return unless saved_change_to_serialized_value?

      current_value = serialized_value.is_a?(Hash) ? serialized_value['value'] : serialized_value
      return if current_value.blank?

      Integrations::Clickup::RegisterWebhookJob.perform_later
    end
  end
end
