require 'rails_helper'

RSpec.describe Integrations::Clickup::FieldMap do
  describe '.ambiente_option_for' do
    it 'maps the auris prod URL to Produção' do
      expect(described_class.ambiente_option_for('https://chat.auris.ia.br'))
        .to eq(described_class::AMBIENTE_OPTIONS[:producao])
      expect(described_class.ambiente_option_for('https://chat.auris.ia.br/'))
        .to eq(described_class::AMBIENTE_OPTIONS[:producao])
    end

    it 'maps everything else (homolog, dev, empty) to Homologação so ops can filter test noise' do
      %w[https://chat-hmlg.auris.ia.br http://localhost:3000 nil].each do |value|
        expect(described_class.ambiente_option_for(value))
          .to eq(described_class::AMBIENTE_OPTIONS[:homologacao])
      end
      expect(described_class.ambiente_option_for(nil))
        .to eq(described_class::AMBIENTE_OPTIONS[:homologacao])
    end
  end

  describe '.canal_option_for' do
    it 'sub-maps a WhatsApp inbox by provider (cloud / baileys / zapi)' do
      whatsapp = instance_double(Inbox, channel_type: 'Channel::Whatsapp',
                                        channel: instance_double(Channel::Whatsapp, provider: 'whatsapp_cloud'))
      expect(described_class.canal_option_for(whatsapp))
        .to eq(described_class::CANAL_OPTIONS['Channel::Whatsapp']['whatsapp_cloud'])

      baileys = instance_double(Inbox, channel_type: 'Channel::Whatsapp',
                                       channel: instance_double(Channel::Whatsapp, provider: 'baileys'))
      expect(described_class.canal_option_for(baileys))
        .to eq(described_class::CANAL_OPTIONS['Channel::Whatsapp']['baileys'])
    end

    it 'returns the flat option id for non-WhatsApp channels' do
      simulator = instance_double(Inbox, channel_type: 'Channel::Simulator', channel: nil)
      expect(described_class.canal_option_for(simulator))
        .to eq(described_class::CANAL_OPTIONS['Channel::Simulator'])
    end

    # Guard: unmapped channels (Line, Telegram, etc.) return nil so the caller
    # can drop the Canal field from the payload — better than sending a bogus
    # option id that ClickUp would reject.
    it 'returns nil for a channel we have not mapped' do
      telegram = instance_double(Inbox, channel_type: 'Channel::Telegram', channel: nil)
      expect(described_class.canal_option_for(telegram)).to be_nil
    end

    it 'returns nil for a nil inbox (no conversation.inbox on the ticket, edge case)' do
      expect(described_class.canal_option_for(nil)).to be_nil
    end
  end
end
