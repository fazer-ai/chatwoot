require 'rails_helper'

RSpec.describe DisparoTarget do
  describe 'associations' do
    it { is_expected.to belong_to(:disparo) }
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to belong_to(:contact) }
    it { is_expected.to belong_to(:inbox).optional }
    it { is_expected.to have_many(:disparo_events).dependent(:destroy) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:state).with_values(pending: 0, queued: 1, skipped: 2, cancelled: 3) }
  end

  describe 'defaults' do
    it 'defaults state to pending, skip_reasons to [], shadow_run to false and assigns a dispatch_id' do
      target = create(:disparo_target)
      expect(target.state).to eq('pending')
      expect(target.skip_reasons).to eq([])
      expect(target.shadow_run).to be(false)
      expect(target.dispatch_id).to be_present
    end
  end

  describe 'grain (disparo_id, conversation_id, contact_id)' do
    it 'rejects a duplicate target for the same disparo/conversation/contact' do
      target = create(:disparo_target)
      duplicate = build(:disparo_target, disparo: target.disparo, conversation: target.conversation, contact: target.contact)
      expect(duplicate.valid?).to be(false)
    end

    it 'allows the same contact in a different conversation of the same disparo' do
      target = create(:disparo_target)
      other_conversation = create(:conversation, account: target.disparo.account, contact: target.contact)
      sibling = build(:disparo_target, disparo: target.disparo, conversation: other_conversation, contact: target.contact)
      expect(sibling.valid?).to be(true)
    end
  end
end
