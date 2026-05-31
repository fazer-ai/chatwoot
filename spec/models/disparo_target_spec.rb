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

  # disparo_targets is DERIVED data; the cascade/nullify lives at the DB level (FK on_delete),
  # NOT via any reverse association on the core models. Assert via DB existence + reload, since
  # AR in-memory state does not reflect a DB-level cascade.
  describe 'DB-level FK lifecycle on core entities' do
    it 'cascades when its conversation is deleted, leaving sibling and unrelated targets untouched' do
      target = create(:disparo_target)
      account = target.disparo.account
      contact = target.contact

      # Sibling: same contact, another conversation of the same disparo (shares the deleted conv's contact).
      sibling_conversation = create(:conversation, account: account, contact: contact)
      sibling = create(:disparo_target, disparo: target.disparo, conversation: sibling_conversation, contact: contact)
      # Unrelated target in a completely separate disparo/conversation/contact.
      other = create(:disparo_target)

      conversation_id = target.conversation_id
      target.conversation.delete

      expect(described_class.exists?(target.id)).to be(false)
      # Core data is NOT collaterally deleted: the contact, the sibling conversation/target, and the
      # unrelated target all survive (only the deleted conversation's own targets cascade).
      expect(Contact.exists?(contact.id)).to be(true)
      expect(Conversation.exists?(sibling_conversation.id)).to be(true)
      expect(described_class.exists?(sibling.id)).to be(true)
      expect(described_class.exists?(other.id)).to be(true)
      expect(Conversation.exists?(conversation_id)).to be(false)
    end

    it 'cascades when its contact is deleted, leaving unrelated targets untouched' do
      target = create(:disparo_target)
      other = create(:disparo_target)

      target.contact.delete

      expect(described_class.exists?(target.id)).to be(false)
      expect(described_class.exists?(other.id)).to be(true)
    end

    it 'does NOT block an inbox delete and nullifies the target inbox_id (target survives)' do
      target = create(:disparo_target)
      inbox = target.inbox
      expect(inbox).to be_present

      expect { inbox.delete }.not_to raise_error
      expect(Inbox.exists?(inbox.id)).to be(false)

      target.reload
      expect(target.inbox_id).to be_nil
      expect(described_class.exists?(target.id)).to be(true)
    end
  end
end
