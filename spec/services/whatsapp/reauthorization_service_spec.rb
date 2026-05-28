require 'rails_helper'

describe Whatsapp::ReauthorizationService do
  let(:account) { create(:account) }
  let(:initial_provider_config) do
    {
      'api_key' => 'old_token',
      'phone_number_id' => 'old_phone_number_id',
      'business_account_id' => 'old_waba_id',
      'webhook_verify_token' => 'verify_token'
    }
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+1234567890',
                              provider_config: initial_provider_config, validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }

  let(:access_token) { 'new_access_token' }
  let(:phone_info) do
    {
      phone_number_id: 'new_phone_number_id',
      phone_number: '+1234567890',
      verified: true,
      business_name: 'New Business Name'
    }
  end

  let(:service) do
    described_class.new(
      account: account,
      inbox_id: inbox.id,
      phone_number_id: 'new_phone_number_id',
      waba_id: 'new_waba_id'
    )
  end

  before do
    # Stub the Meta Graph call that backs `validate_provider_config?` so the
    # save inside ReauthorizationService doesn't reach out to the network and
    # doesn't fail validation with a network error.
    stub_request(:get, %r{https://graph.facebook.com/.*/message_templates}).to_return(status: 200, body: { data: [] }.to_json)
  end

  describe '#perform' do
    it 'stores the waba_id in business_account_id' do
      service.perform(access_token, phone_info)
      expect(channel.reload.provider_config['business_account_id']).to eq('new_waba_id')
    end

    it 'updates api_key and phone_number_id' do
      service.perform(access_token, phone_info)
      reloaded_config = channel.reload.provider_config
      expect(reloaded_config['api_key']).to eq('new_access_token')
      expect(reloaded_config['phone_number_id']).to eq('new_phone_number_id')
    end

    it 'preserves the existing webhook_verify_token' do
      service.perform(access_token, phone_info)
      expect(channel.reload.provider_config['webhook_verify_token']).to eq('verify_token')
    end

    it 'updates the inbox name when business_name is provided' do
      service.perform(access_token, phone_info)
      expect(inbox.reload.name).to eq('New Business Name')
    end

    it 'raises when the phone number does not match' do
      mismatched_phone_info = phone_info.merge(phone_number: '+0987654321')
      expect { service.perform(access_token, mismatched_phone_info) }
        .to raise_error do |error|
          expect(error.class.name).to eq('StandardError')
          expect(error.message).to match(/Phone number mismatch/)
        end
    end
  end
end
