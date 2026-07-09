# Registers (or re-registers) the ClickUp webhook that pushes status and
# custom-field updates back into AurisChat. Triggered from
# `Integrations::Clickup::ConfigService` whenever the API key is saved.
#
# We keep the reference (webhook id + secret) in InstallationConfig so the
# signature-verification middleware can look up the secret without
# spawning another API call, and so a fresh install always calls
# `delete_webhook` on the previous one before creating a new one.
class Integrations::Clickup::RegisterWebhookJob < ApplicationJob
  queue_as :low

  def perform
    client = Integrations::Clickup::Client.new
    return unless client.configured?

    delete_previous_webhook(client)
    register_new_webhook(client)
  end

  private

  def delete_previous_webhook(client)
    existing_id = InstallationConfig.find_by(name: 'CLICKUP_WEBHOOK_ID')&.value.presence
    return if existing_id.blank?

    client.delete_webhook(existing_id)
  rescue Integrations::Clickup::Client::Error => e
    Rails.logger.warn("[ClickUp] failed to delete previous webhook #{existing_id}: #{e.message}")
  end

  def register_new_webhook(client)
    response = client.create_webhook(
      team_id: Integrations::Clickup::FieldMap::TEAM_ID,
      endpoint: webhook_endpoint,
      events: Integrations::Clickup::FieldMap::WEBHOOK_EVENTS
    )

    webhook = response['webhook'] || {}
    upsert_config('CLICKUP_WEBHOOK_ID', webhook['id'].to_s)
    upsert_config('CLICKUP_WEBHOOK_SECRET', webhook['secret'].to_s)
  end

  # InstallationConfig requires `serialized_value` at insert time (the
  # `value` reader/writer piggybacks off it), so a bare find_or_create_by!
  # on `name:` trips a NOT NULL constraint. `first_or_create!(value: ...)`
  # is the pattern the SuperAdmin app_configs controller uses.
  def upsert_config(name, value)
    record = InstallationConfig.where(name: name).first_or_create!(value: value, locked: false)
    record.update!(value: value) if record.value != value
  end

  def webhook_endpoint
    base = ENV.fetch('FRONTEND_URL', '').presence || 'http://localhost:3000'
    "#{base.chomp('/')}/webhooks/clickup"
  end
end
