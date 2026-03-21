# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::Draft do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:channel).class_name('InternalChat::Channel') }
    it { is_expected.to belong_to(:parent).class_name('InternalChat::Message').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:content) }

    describe 'uniqueness of user_id scoped to channel' do
      subject { create(:internal_chat_draft) }

      it { is_expected.to validate_uniqueness_of(:user_id).scoped_to([:internal_chat_channel_id, :parent_id]) }
    end
  end

  describe 'scopes' do
    describe '.recent' do
      it 'returns drafts ordered by updated_at descending' do
        account = create(:account)
        user = create(:user, account: account)
        channel1 = create(:internal_chat_channel, account: account)
        channel2 = create(:internal_chat_channel, account: account)

        old_draft = create(:internal_chat_draft, account: account, user: user, channel: channel1,
                                                 updated_at: 2.hours.ago)
        new_draft = create(:internal_chat_draft, account: account, user: user, channel: channel2,
                                                 updated_at: 1.minute.ago)

        expect(described_class.recent).to eq([new_draft, old_draft])
      end
    end
  end

  describe 'parent association' do
    it 'allows creating a draft with a parent message' do
      account = create(:account)
      user = create(:user, account: account)
      channel = create(:internal_chat_channel, account: account)
      parent_message = create(:internal_chat_message, account: account, channel: channel, sender: user)

      draft = create(:internal_chat_draft, account: account, user: user, channel: channel, parent: parent_message)

      expect(draft.parent).to eq(parent_message)
    end

    it 'does not allow duplicate drafts for same user and channel' do
      account = create(:account)
      user = create(:user, account: account)
      channel = create(:internal_chat_channel, account: account)

      create(:internal_chat_draft, account: account, user: user, channel: channel)

      duplicate = build(:internal_chat_draft, account: account, user: user, channel: channel)
      expect(duplicate).not_to be_valid
    end
  end
end
