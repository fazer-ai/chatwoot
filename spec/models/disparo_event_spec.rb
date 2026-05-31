require 'rails_helper'

RSpec.describe DisparoEvent do
  describe 'associations' do
    it { is_expected.to belong_to(:disparo_target) }
  end

  describe 'enums' do
    it {
      expect(subject).to define_enum_for(:event_type).with_values(
        queued: 0, sending: 1, sent: 2, delivered: 3, read: 4, replied: 5,
        failed: 6, skipped: 7, cancelled: 8, retried: 9, reconciled_unknown: 10
      )
    }
  end

  describe 'append-only timeline' do
    it 'persists with a payload default and a created_at' do
      event = create(:disparo_event)
      expect(event.payload).to eq({})
      expect(event.created_at).to be_present
    end
  end
end
