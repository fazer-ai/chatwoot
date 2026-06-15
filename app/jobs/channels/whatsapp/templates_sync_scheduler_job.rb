class Channels::Whatsapp::TemplatesSyncSchedulerJob < ApplicationJob
  queue_as :low

  # Providers whose `sync_templates` implementation is a no-op — there is no
  # template registry exposed by WhatsApp Web / Z-API, so persisting an
  # empty list and re-checking is pure churn. Without this filter, every
  # Baileys / Z-API channel sits at `message_templates_last_updated = NULL`
  # forever and monopolizes the 25-channel batch (NULLs sort first by
  # design), which silently starves the providers that actually need the
  # refresh (whatsapp_cloud + 360Dialog).
  NON_SYNCABLE_PROVIDERS = %w[baileys zapi].freeze

  def perform
    Channel::Whatsapp.where.not(provider: NON_SYNCABLE_PROVIDERS)
                     .order(Arel.sql('message_templates_last_updated IS NULL DESC, message_templates_last_updated ASC'))
                     .where('message_templates_last_updated <= ? OR message_templates_last_updated IS NULL', 3.hours.ago)
                     .limit(Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT)
                     .each do |channel|
      Channels::Whatsapp::TemplatesSyncJob.perform_later(channel)
    end
  end
end
