require 'rails_helper'

describe Whatsapp::CanonicalPhoneResolverService do
  let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false) }

  describe '#resolve' do
    context 'when the number is already registered in the canonical (13d) format' do
      it 'returns the 13d form without trying the 12d alternative' do
        phone = '5531998010696'
        registered = { 'exists' => true, 'jid' => "#{phone}@s.whatsapp.net" }
        expect(whatsapp_channel).to receive(:on_whatsapp).with("#{phone}@s.whatsapp.net").and_return(registered)
        expect(whatsapp_channel).not_to receive(:on_whatsapp).with('553198010696@s.whatsapp.net')

        result = described_class.new(channel: whatsapp_channel, phone: phone).resolve

        expect(result).to eq(phone)
      end
    end

    context 'when the operator typed the legacy 12d format but the number is actually registered in 13d' do
      it 'normalizes to 13d and returns it' do
        phone_12d = '553198010696'
        phone_13d = '5531998010696'
        expect(whatsapp_channel).to receive(:on_whatsapp).with("#{phone_13d}@s.whatsapp.net").and_return({ 'exists' => true })

        result = described_class.new(channel: whatsapp_channel, phone: phone_12d).resolve

        # Brazilian normalizer turns 12d → 13d before the on_whatsapp call,
        # so 13d is the first (and only successful) candidate here.
        expect(result).to eq(phone_13d)
      end
    end

    context 'when the WhatsApp account is registered under the pre-2012 12d format' do
      it 'returns the 12d form after the 13d candidate fails' do
        phone_typed = '5531998010696'
        phone_canonical = '553198010696'
        expect(whatsapp_channel).to receive(:on_whatsapp).with("#{phone_typed}@s.whatsapp.net").and_return({ 'exists' => false })
        expect(whatsapp_channel).to receive(:on_whatsapp).with("#{phone_canonical}@s.whatsapp.net").and_return({ 'exists' => true })

        result = described_class.new(channel: whatsapp_channel, phone: phone_typed).resolve

        expect(result).to eq(phone_canonical)
      end
    end

    context 'when neither candidate is registered' do
      it 'returns the input phone unchanged' do
        phone = '5531998010696'
        allow(whatsapp_channel).to receive(:on_whatsapp).and_return({ 'exists' => false })

        result = described_class.new(channel: whatsapp_channel, phone: phone).resolve

        expect(result).to eq(phone)
      end
    end

    context 'when on_whatsapp raises' do
      it 'falls back to the input phone and logs a warning' do
        phone = '5531998010696'
        allow(whatsapp_channel).to receive(:on_whatsapp).and_raise(StandardError, 'baileys-api down')
        allow(Rails.logger).to receive(:warn)

        result = described_class.new(channel: whatsapp_channel, phone: phone).resolve

        expect(result).to eq(phone)
        expect(Rails.logger).to have_received(:warn).with(/canonical-phone.*baileys-api down/)
      end
    end

    context 'when the channel is not Baileys' do
      let!(:cloud_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

      it 'skips the lookup entirely' do
        phone = '5531998010696'
        expect(cloud_channel).not_to receive(:on_whatsapp)

        result = described_class.new(channel: cloud_channel, phone: phone).resolve

        expect(result).to eq(phone)
      end
    end

    context 'when the phone is not Brazilian' do
      it 'skips the lookup' do
        phone = '14155551234'
        expect(whatsapp_channel).not_to receive(:on_whatsapp)

        result = described_class.new(channel: whatsapp_channel, phone: phone).resolve

        expect(result).to eq(phone)
      end
    end

    it 'tolerates the leading "+" in the input' do
      phone = '+5531998010696'
      expect(whatsapp_channel).to receive(:on_whatsapp).with('5531998010696@s.whatsapp.net').and_return({ 'exists' => true })

      result = described_class.new(channel: whatsapp_channel, phone: phone).resolve

      expect(result).to eq('5531998010696')
    end
  end
end
