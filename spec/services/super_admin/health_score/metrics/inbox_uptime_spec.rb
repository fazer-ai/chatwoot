require 'rails_helper'

RSpec.describe SuperAdmin::HealthScore::Metrics::InboxUptime do
  let(:on) { Date.current }
  let(:account) { create(:account) }

  it 'returns missing when the account has no WhatsApp inboxes' do
    result = described_class.new(account, on: on).compute

    expect(result).to include(missing: true, reason: 'no_whatsapp_inboxes')
  end

  it 'returns 100 when every WhatsApp inbox is currently connected' do
    create(:channel_whatsapp, account: account, phone_number: '+5511990000001', provider: 'baileys',
                              provider_connection: { 'connection' => 'open' },
                              validate_provider_config: false, sync_templates: false)
    create(:channel_whatsapp, account: account, phone_number: '+5511990000002', provider: 'zapi',
                              provider_connection: { 'connection' => 'open' },
                              validate_provider_config: false, sync_templates: false)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(100)
    expect(result.dig(:raw, :all_disconnected)).to be false
  end

  it 'returns 0 (worst case) when any WhatsApp inbox is disconnected' do
    create(:channel_whatsapp, account: account, phone_number: '+5511990000003', provider: 'baileys',
                              provider_connection: { 'connection' => 'open' },
                              validate_provider_config: false, sync_templates: false)
    create(:channel_whatsapp, account: account, phone_number: '+5511990000004', provider: 'baileys',
                              provider_connection: { 'connection' => 'close' },
                              validate_provider_config: false, sync_templates: false)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(0)
    expect(result.dig(:raw, :all_disconnected)).to be false
    expect(result.dig(:raw, :worst_inbox_pct)).to eq(0.0)
  end

  it 'flags all_disconnected when every WhatsApp inbox is down' do
    create(:channel_whatsapp, account: account, phone_number: '+5511990000005', provider: 'baileys',
                              provider_connection: { 'connection' => 'close' },
                              validate_provider_config: false, sync_templates: false)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(0)
    expect(result.dig(:raw, :all_disconnected)).to be true
  end

  it 'treats whatsapp_cloud as always connected (no socket pairing)' do
    create(:channel_whatsapp, account: account, phone_number: '+5511990000006', provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(100)
  end
end
