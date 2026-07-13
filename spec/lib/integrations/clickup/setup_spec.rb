require 'rails_helper'

RSpec.describe Integrations::Clickup::Setup do
  # The feedback flag icon on messages, the "Meus Tickets" sidebar item,
  # and the /tickets route all key off `ready?`. Anything short of BOTH
  # signals present hides the feature to avoid dead-end tickets that never
  # get an update after the ClickUp side goes cold.
  describe '.ready?' do
    def stub_config(name, value)
      allow(GlobalConfig).to receive(:get).with(name).and_return(name => value)
    end

    it 'is true when both the API key and the webhook are configured' do
      stub_config('CLICKUP_API_KEY', 'sk_test_key')
      stub_config('CLICKUP_WEBHOOK_ID', 'wh_abc')

      expect(described_class.ready?).to be true
    end

    it 'is false when the API key is missing' do
      stub_config('CLICKUP_API_KEY', '')
      stub_config('CLICKUP_WEBHOOK_ID', 'wh_abc')

      expect(described_class.ready?).to be false
    end

    it 'is false when the webhook has not been registered yet' do
      stub_config('CLICKUP_API_KEY', 'sk_test_key')
      stub_config('CLICKUP_WEBHOOK_ID', nil)

      expect(described_class.ready?).to be false
    end

    # Whitespace-only values are treated the same as blank so a copy-paste
    # accident on Super Admin doesn't ship a half-configured integration.
    it 'treats whitespace-only values as unconfigured' do
      stub_config('CLICKUP_API_KEY', '   ')
      stub_config('CLICKUP_WEBHOOK_ID', 'wh_abc')

      expect(described_class.ready?).to be false
    end
  end
end
