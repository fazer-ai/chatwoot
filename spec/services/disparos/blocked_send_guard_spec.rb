require 'rails_helper'

RSpec.describe Disparos::BlockedSendGuard do
  describe '.block!' do
    it 'hard-raises BlockedSendBeta0 with the exact message' do
      expect { described_class.block! }.to raise_error do |error|
        expect(error.class.name).to eq('CustomExceptions::Disparos::BlockedSendBeta0')
        expect(error.message).to eq('blocked_send_beta_0')
      end
    end

    it 'raises regardless of the context passed in' do
      expect { described_class.block!(disparo_id: 1, contact_id: 2) }.to raise_error do |error|
        expect(error.message).to eq('blocked_send_beta_0')
      end
    end

    it 'raises in the production environment too (there is no enable path)' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      expect { described_class.block! }.to raise_error do |error|
        expect(error.message).to eq('blocked_send_beta_0')
      end
    end
  end
end
