require 'rails_helper'

describe Disparos::ConfigFingerprint do
  let(:account) { create(:account) }
  let(:cloud_inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:filter) { { 'kanban_steps' => %w[3 5], 'label' => %w[vip gold] } }

  def build_disparo(**overrides)
    attrs = { account: account, template_name: 'sample_shipping_confirmation', audience_filter: filter }.merge(overrides)
    disparo = create(:disparo, **attrs)
    create(:disparo_inbox, disparo: disparo, inbox: cloud_inbox)
    disparo
  end

  describe '.for' do
    it 'is deterministic for the same config across reloads' do
      disparo = build_disparo
      first = described_class.for(disparo)
      expect(described_class.for(Disparo.find(disparo.id))).to eq(first)
    end

    it 'is stable across audience_filter key/value ordering (canonicalized)' do
      a = build_disparo(audience_filter: { 'kanban_steps' => %w[5 3], 'label' => %w[gold vip] })
      b = build_disparo(audience_filter: { 'label' => %w[vip gold], 'kanban_steps' => %w[3 5] })
      expect(described_class.for(a)).to eq(described_class.for(b))
    end

    it 'changes when template_name changes' do
      disparo = build_disparo
      before = described_class.for(disparo)
      disparo.update!(template_name: 'other_template')
      expect(described_class.for(disparo)).not_to eq(before)
    end

    it 'changes when template_category changes' do
      disparo = build_disparo
      before = described_class.for(disparo)
      disparo.update!(template_category: :marketing)
      expect(described_class.for(disparo)).not_to eq(before)
    end

    it 'changes when conversation_status changes' do
      disparo = build_disparo
      before = described_class.for(disparo)
      disparo.update!(conversation_status: :all)
      expect(described_class.for(disparo)).not_to eq(before)
    end

    it 'changes when the audience_filter values change' do
      disparo = build_disparo
      before = described_class.for(disparo)
      disparo.update!(audience_filter: { 'kanban_steps' => %w[9], 'label' => %w[vip] })
      expect(described_class.for(disparo)).not_to eq(before)
    end

    it 'changes when the selected inbox set changes' do
      disparo = build_disparo
      before = described_class.for(disparo)
      second_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                               sync_templates: false, validate_provider_config: false).inbox
      create(:disparo_inbox, disparo: disparo, inbox: second_inbox)
      expect(described_class.for(disparo)).not_to eq(before)
    end
  end
end
