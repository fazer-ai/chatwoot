require 'rails_helper'

describe Disparos::TemplateCategory do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end

  describe '.for_channel — Meta-value -> enum mapping' do
    let(:templates) do
      [
        { 'name' => 'promo_blast', 'status' => 'approved', 'category' => 'MARKETING' },
        { 'name' => 'otp_code', 'status' => 'APPROVED', 'category' => 'AUTHENTICATION' },
        { 'name' => 'ticket_update', 'status' => 'approved', 'category' => 'UTILITY' },
        { 'name' => 'legacy_shipping', 'status' => 'approved', 'category' => 'SHIPPING_UPDATE' },
        { 'name' => 'legacy_account', 'status' => 'approved', 'category' => 'ACCOUNT_UPDATE' },
        { 'name' => 'pending_promo', 'status' => 'PENDING', 'category' => 'MARKETING' },
        { 'name' => 'no_category', 'status' => 'approved' }
      ]
    end

    it 'maps MARKETING -> marketing' do
      expect(described_class.for_channel(channel, 'promo_blast')).to eq('marketing')
    end

    it 'maps AUTHENTICATION -> authentication' do
      expect(described_class.for_channel(channel, 'otp_code')).to eq('authentication')
    end

    it 'maps UTILITY -> utility' do
      expect(described_class.for_channel(channel, 'ticket_update')).to eq('utility')
    end

    it 'maps legacy SHIPPING_UPDATE -> utility' do
      expect(described_class.for_channel(channel, 'legacy_shipping')).to eq('utility')
    end

    it 'maps legacy ACCOUNT_UPDATE -> utility' do
      expect(described_class.for_channel(channel, 'legacy_account')).to eq('utility')
    end

    it 'matches the template name CASE-INSENSITIVELY by default (generous classifier)' do
      expect(described_class.for_channel(channel, 'PROMO_BLAST')).to eq('marketing')
    end

    it 'matches the template name EXACT-case when exact: true (a differently-cased name does not resolve)' do
      expect(described_class.for_channel(channel, 'PROMO_BLAST', exact: true)).to be_nil
    end

    it 'still resolves the exact-cased name when exact: true' do
      expect(described_class.for_channel(channel, 'promo_blast', exact: true)).to eq('marketing')
    end

    it 'returns nil for a template that is not approved' do
      expect(described_class.for_channel(channel, 'pending_promo')).to be_nil
    end

    it 'returns nil for an approved template carrying no category' do
      expect(described_class.for_channel(channel, 'no_category')).to be_nil
    end

    it 'returns nil when the template name is not present in the channel' do
      expect(described_class.for_channel(channel, 'unknown_template')).to be_nil
    end

    it 'returns nil for a blank template name' do
      expect(described_class.for_channel(channel, '')).to be_nil
    end
  end

  describe '.for_channel — nil-safe channel handling' do
    let(:templates) { [] }

    it 'returns nil for a nil channel' do
      expect(described_class.for_channel(nil, 'promo_blast')).to be_nil
    end

    it 'returns nil when the channel has an empty template set' do
      expect(described_class.for_channel(channel, 'promo_blast')).to be_nil
    end
  end
end
