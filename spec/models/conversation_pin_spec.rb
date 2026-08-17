require 'rails_helper'

RSpec.describe ConversationPin do
  context 'with validations' do
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:conversation_id) }
    it { is_expected.to validate_presence_of(:user_id) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    it 'ensures account is present' do
      conversation = create(:conversation, account: account)
      conversation_pin = build(:conversation_pin, conversation: conversation, user: user, account_id: nil)
      conversation_pin.valid?
      expect(conversation_pin.account_id).to eq(conversation.account_id)
    end

    it 'does not allow the same user to pin a conversation twice' do
      conversation = create(:conversation, account: account)
      create(:conversation_pin, conversation: conversation, user: user, account: account)
      duplicate = build(:conversation_pin, conversation: conversation, user: user, account: account)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.messages[:user_id]).to eq(['has already been taken'])
    end

    it 'allows two users to pin the same conversation' do
      conversation = create(:conversation, account: account)
      other_user = create(:user, account: account)
      create(:conversation_pin, conversation: conversation, user: user, account: account)

      expect(build(:conversation_pin, conversation: conversation, user: other_user, account: account)).to be_valid
    end
  end

  describe 'resolved conversations' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    it 'rejects a pin on a resolved conversation' do
      conversation = create(:conversation, account: account, status: :resolved)
      pin = build(:conversation_pin, conversation: conversation, user: user, account: account)

      expect(pin).not_to be_valid
      expect(pin.errors.full_messages).to eq(['A resolved conversation cannot be pinned.'])
    end

    it 'allows a pin on a pending conversation' do
      conversation = create(:conversation, account: account, status: :pending)

      expect(build(:conversation_pin, conversation: conversation, user: user, account: account)).to be_valid
    end

    it 'does not free the slot of an existing pin when the conversation is resolved later' do
      conversation = create(:conversation, account: account)
      pin = create(:conversation_pin, conversation: conversation, user: user, account: account)

      expect(pin.reload).to be_persisted
    end
  end

  describe 'pin limit' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    before do
      described_class::MAX_PER_USER.times do
        create(:conversation_pin, conversation: create(:conversation, account: account), user: user, account: account)
      end
    end

    it 'rejects a pin beyond the limit' do
      extra = build(:conversation_pin, conversation: create(:conversation, account: account), user: user, account: account)

      expect(extra).not_to be_valid
      expect(extra.errors.full_messages).to eq(["You can pin up to #{described_class::MAX_PER_USER} conversations."])
    end

    it 'counts the limit per account' do
      other_account = create(:account)
      create(:account_user, account: other_account, user: user)
      conversation = create(:conversation, account: other_account)

      expect(build(:conversation_pin, conversation: conversation, user: user, account: other_account)).to be_valid
    end

    it 'counts the limit per user' do
      other_user = create(:user, account: account)
      conversation = create(:conversation, account: account)

      expect(build(:conversation_pin, conversation: conversation, user: other_user, account: account)).to be_valid
    end

    it 'frees a slot when a pin is removed' do
      described_class.where(user: user).first.destroy!

      expect(build(:conversation_pin, conversation: create(:conversation, account: account), user: user, account: account)).to be_valid
    end
  end

  describe 'inbox access' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:user) { create(:user, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:inbox_member) { create(:inbox_member, user: user, inbox: inbox) }

    it 'removes the pins of an agent dropped from the inbox' do
      create(:conversation_pin, conversation: conversation, user: user, account: account)

      expect { inbox_member.destroy! }.to change(described_class, :count).from(1).to(0)
    end

    it 'keeps the pins of the agents still in the inbox' do
      other_user = create(:user, account: account)
      create(:inbox_member, user: other_user, inbox: inbox)
      create(:conversation_pin, conversation: conversation, user: other_user, account: account)

      expect { inbox_member.destroy! }.not_to change(described_class, :count)
    end

    it 'keeps the pins of the same agent in other inboxes' do
      other_conversation = create(:conversation, account: account)
      create(:conversation_pin, conversation: other_conversation, user: user, account: account)

      expect { inbox_member.destroy! }.not_to change(described_class, :count)
    end
  end

  describe 'events' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:conversation) { create(:conversation, account: account) }

    it 'dispatches a pinned event with serialized data' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      pin = create(:conversation_pin, conversation: conversation, user: user, account: account)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        described_class::CONVERSATION_PINNED,
        kind_of(Time),
        conversation_pin: {
          account_id: account.id,
          user_id: user.id,
          conversation_id: conversation.display_id,
          pinned_at: pin.created_at.to_f
        }
      )
    end

    it 'dispatches an unpinned event with serialized data' do
      pin = create(:conversation_pin, conversation: conversation, user: user, account: account)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      pin.destroy!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        described_class::CONVERSATION_UNPINNED,
        kind_of(Time),
        conversation_pin: {
          account_id: account.id,
          user_id: user.id,
          conversation_id: conversation.display_id,
          pinned_at: pin.created_at.to_f
        }
      )
    end

    it 'does not dispatch when the conversation is already gone' do
      pin = create(:conversation_pin, conversation: conversation, user: user, account: account)
      allow(pin).to receive_messages(conversation: nil)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      expect { pin.destroy! }.not_to raise_error
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
    end
  end
end
