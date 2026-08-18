require 'rails_helper'

RSpec.describe Whatsapp::Session::Outbound::SourceIdReservation do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, inbox: inbox, account: channel.account) }
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: channel.account, message_type: :outgoing)
  end

  it 'generates ids in the shape WhatsApp clients use' do
    expect(described_class.generate).to match(/\A3EB0[0-9A-F]{18}\z/)
  end

  it 'reserves once and reuses the reservation on a retry' do
    reserved = described_class.reserve(message)

    expect(reserved).to be_present
    expect(described_class.reserve(message.reload)).to eq(reserved)
  end

  # Whoever moves `source_id` from blank to set owns the revoke of a message deleted
  # mid-send, and three writers race for it. A conditional UPDATE is what makes the
  # answer unambiguous no matter how they interleave.
  describe '.claim_source_id' do
    it 'is won by exactly one caller' do
      first = described_class.claim_source_id(message, '3EB0FIRST')
      second = described_class.claim_source_id(message.reload, '3EB0SECOND')

      expect([first, second]).to eq([true, false])
      expect(message.reload.source_id).to eq('3EB0FIRST')
    end

    it 'claims nothing without an id to write' do
      expect(described_class.claim_source_id(message, nil)).to be(false)
      expect(message.reload.source_id).to be_nil
    end
  end
end
