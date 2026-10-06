# Moves every Z-API inbox from the old webhook URL, which carried only the phone number, to the
# one that carries a token. Until the new URL is confirmed the old one keeps taking the inbox's
# events, so an inbox this job cannot reach (Z-API down, credentials revoked) keeps working the
# way it did and is listed in the log. Running the job again, or setting the inbox up again from
# its settings page, moves it.
class Migration::ZapiWebhookUrlJob < ApplicationJob
  queue_as :async_database_migration

  def perform
    stats = { moved: 0, failed: 0 }

    Channel::Whatsapp.where(provider: 'zapi').find_each do |channel|
      next if channel.provider_config['webhook_url_confirmed']

      Whatsapp::Providers::WhatsappZapiService.new(whatsapp_channel: channel).register_webhooks
      stats[:moved] += 1
    rescue StandardError => e
      stats[:failed] += 1
      Rails.logger.warn("[zapi-webhook-url] still on the old URL channel_id=#{channel.id} error=#{e.class}: #{e.message}")
    end

    Rails.logger.info("[zapi-webhook-url] completed #{stats.inspect}")
    stats
  end
end
