require 'rails_helper'

RSpec.describe Channels::Whatsapp::TemplatesSyncSchedulerJob do
  it 'enqueues the job' do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
      .on_queue('low')
  end

  context 'when called' do
    it 'schedules templates_sync_jobs for channels where templates need to be updated' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      non_synced = create(:channel_whatsapp, sync_templates: false, message_templates_last_updated: nil)
      synced_recently = create(:channel_whatsapp, sync_templates: false, message_templates_last_updated: Time.zone.now)
      synced_old = create(:channel_whatsapp, sync_templates: false, message_templates_last_updated: 4.hours.ago)
      described_class.perform_now
      expect(Channels::Whatsapp::TemplatesSyncJob).not_to(
        have_been_enqueued.with(synced_recently).on_queue('low')
      )
      expect(Channels::Whatsapp::TemplatesSyncJob).to(
        have_been_enqueued.with(synced_old).on_queue('low')
      )
      expect(Channels::Whatsapp::TemplatesSyncJob).to(
        have_been_enqueued.with(non_synced).on_queue('low')
      )
    end

    it 'schedules templates_sync_job for oldest synced channels first' do
      stub_const('Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT', 2)
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      non_synced = create(:channel_whatsapp, sync_templates: false, message_templates_last_updated: nil)
      synced_recently = create(:channel_whatsapp, sync_templates: false, message_templates_last_updated: 4.hours.ago)
      synced_old = create(:channel_whatsapp, sync_templates: false, message_templates_last_updated: 6.hours.ago)
      described_class.perform_now
      expect(Channels::Whatsapp::TemplatesSyncJob).not_to(
        have_been_enqueued.with(synced_recently).on_queue('low')
      )
      expect(Channels::Whatsapp::TemplatesSyncJob).to(
        have_been_enqueued.with(synced_old).on_queue('low')
      )
      expect(Channels::Whatsapp::TemplatesSyncJob).to(
        have_been_enqueued.with(non_synced).on_queue('low')
      )
    end

    # Regression guard: Baileys / Z-API have no template registry; their
    # `sync_templates` is a no-op that never stamps the timestamp. Before
    # this filter, those channels (which create as `last_updated = NULL`)
    # monopolized the 25-channel batch every 5 minutes, starving the
    # Cloud / 360Dialog channels that actually need refreshing — leaving
    # some Cloud inboxes with templates months out of date.
    it 'does not enqueue templates_sync_job for baileys channels' do
      baileys_channel = create(:channel_whatsapp, provider: 'baileys', sync_templates: false,
                                                  validate_provider_config: false, message_templates_last_updated: nil)
      described_class.perform_now
      expect(Channels::Whatsapp::TemplatesSyncJob).not_to(have_been_enqueued.with(baileys_channel))
    end

    it 'does not enqueue templates_sync_job for zapi channels' do
      zapi_channel = create(:channel_whatsapp, provider: 'zapi', sync_templates: false,
                                               validate_provider_config: false, message_templates_last_updated: nil)
      described_class.perform_now
      expect(Channels::Whatsapp::TemplatesSyncJob).not_to(have_been_enqueued.with(zapi_channel))
    end

    it 'still enqueues cloud channels when baileys / zapi are also present' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      create(:channel_whatsapp, provider: 'baileys', sync_templates: false,
                                validate_provider_config: false, message_templates_last_updated: nil)
      create(:channel_whatsapp, provider: 'zapi', sync_templates: false,
                                validate_provider_config: false, message_templates_last_updated: nil)
      cloud_channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false, message_templates_last_updated: 4.hours.ago)

      described_class.perform_now

      expect(Channels::Whatsapp::TemplatesSyncJob).to(have_been_enqueued.with(cloud_channel))
    end
  end
end
