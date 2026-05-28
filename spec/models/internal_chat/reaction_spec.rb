# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::Reaction do
  describe 'associations' do
    it { is_expected.to belong_to(:message).class_name('InternalChat::Message') }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:emoji) }

    describe 'uniqueness of emoji scoped to message and user' do
      let!(:reaction) { create(:internal_chat_reaction) }

      it 'does not allow the same emoji by the same user on the same message' do
        duplicate = build(:internal_chat_reaction,
                          message: reaction.message,
                          user: reaction.user,
                          emoji: reaction.emoji)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:emoji]).to include('has already been taken')
      end

      it 'allows the same emoji by a different user on the same message' do
        other_user = create(:user)
        other_reaction = build(:internal_chat_reaction,
                               message: reaction.message,
                               user: other_user,
                               emoji: reaction.emoji)
        expect(other_reaction).to be_valid
      end

      it 'allows a different emoji by the same user on the same message' do
        different_reaction = build(:internal_chat_reaction,
                                   message: reaction.message,
                                   user: reaction.user,
                                   emoji: '❤️')
        expect(different_reaction).to be_valid
      end

      it 'allows the same emoji by the same user on a different message' do
        other_message = create(:internal_chat_message)
        other_reaction = build(:internal_chat_reaction,
                               message: other_message,
                               user: reaction.user,
                               emoji: reaction.emoji)
        expect(other_reaction).to be_valid
      end
    end
  end
end
