require 'rails_helper'

# The hook lives in config/initializers/clickup_webhook_hook.rb and only fires
# when the CLICKUP_API_KEY installation config actually saves a new value. It
# must NOT re-enqueue on other config saves (that would spam the ClickUp API)
# and must NOT fire on a save that leaves the value unchanged.
RSpec.describe InstallationConfig do
  describe 'CLICKUP_API_KEY webhook auto-register hook' do
    after do
      described_class.where(name: 'CLICKUP_API_KEY').destroy_all
    end

    it 'enqueues RegisterWebhookJob when the API key value is stored for the first time' do
      expect do
        described_class.where(name: 'CLICKUP_API_KEY').first_or_create!(value: 'pk_abc123', locked: false)
      end.to have_enqueued_job(Integrations::Clickup::RegisterWebhookJob)
    end

    it 'enqueues again when the API key value changes' do
      config = described_class.where(name: 'CLICKUP_API_KEY').first_or_create!(value: 'pk_original', locked: false)

      expect do
        config.update!(value: 'pk_rotated')
      end.to have_enqueued_job(Integrations::Clickup::RegisterWebhookJob)
    end

    it 'does not re-enqueue when saving without changing the value (no-op update)' do
      config = described_class.where(name: 'CLICKUP_API_KEY').first_or_create!(value: 'pk_abc', locked: false)

      expect do
        config.update!(locked: false)
      end.not_to have_enqueued_job(Integrations::Clickup::RegisterWebhookJob)
    end

    it 'ignores saves on unrelated installation configs — only CLICKUP_API_KEY triggers the hook' do
      expect do
        described_class.where(name: 'SOME_OTHER_CONFIG').first_or_create!(value: 'x', locked: false)
      end.not_to have_enqueued_job(Integrations::Clickup::RegisterWebhookJob)
    end

    it 'does not enqueue when the api key value is stored as blank' do
      expect do
        described_class.where(name: 'CLICKUP_API_KEY').first_or_create!(value: '', locked: false)
      end.not_to have_enqueued_job(Integrations::Clickup::RegisterWebhookJob)
    end
  end
end
