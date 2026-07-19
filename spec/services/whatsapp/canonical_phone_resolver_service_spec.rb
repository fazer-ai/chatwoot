require 'rails_helper'

describe Whatsapp::CanonicalPhoneResolverService do
  let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false) }

  describe '#resolve' do
    context 'when the number is registered in the canonical (13d) format' do
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
        expect(whatsapp_channel).to receive(:on_whatsapp).with("#{phone_13d}@s.whatsapp.net")
                                                         .and_return({ 'exists' => true, 'jid' => "#{phone_13d}@s.whatsapp.net" })

        result = described_class.new(channel: whatsapp_channel, phone: phone_12d).resolve

        expect(result).to eq(phone_13d)
      end
    end

    # Real production case: contact phone is 13d, but WhatsApp registered the
    # account under the pre-2012 12d form. baileys-api answers `exists: true`
    # for the 13d probe too, but its `jid` field always carries the actual
    # routing form. Trust that — matching only on `exists` would pick 13d and
    # WA would silently drop the outbound.
    context 'when the 13d probe reports exists=true but the returned jid is the 12d form' do
      it 'returns the jid body from the response, not the input phone' do
        phone_13d = '5591984122323'
        phone_12d = '559184122323'
        expect(whatsapp_channel).to receive(:on_whatsapp).with("#{phone_13d}@s.whatsapp.net")
                                                         .and_return({ 'exists' => true, 'jid' => "#{phone_12d}@s.whatsapp.net" })

        result = described_class.new(channel: whatsapp_channel, phone: phone_13d).resolve

        expect(result).to eq(phone_12d)
      end
    end

    context 'when the 13d probe returns exists=false and only the 12d alternative works' do
      it 'returns the 12d form from the alternative probe response' do
        phone_13d = '5531998010696'
        phone_12d = '553198010696'
        expect(whatsapp_channel).to receive(:on_whatsapp).with("#{phone_13d}@s.whatsapp.net").and_return({ 'exists' => false })
        expect(whatsapp_channel).to receive(:on_whatsapp).with("#{phone_12d}@s.whatsapp.net")
                                                         .and_return({ 'exists' => true, 'jid' => "#{phone_12d}@s.whatsapp.net" })

        result = described_class.new(channel: whatsapp_channel, phone: phone_13d).resolve

        expect(result).to eq(phone_12d)
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
      expect(whatsapp_channel).to receive(:on_whatsapp).with('5531998010696@s.whatsapp.net')
                                                       .and_return({ 'exists' => true, 'jid' => '5531998010696@s.whatsapp.net' })

      result = described_class.new(channel: whatsapp_channel, phone: phone).resolve

      expect(result).to eq('5531998010696')
    end
  end
end
