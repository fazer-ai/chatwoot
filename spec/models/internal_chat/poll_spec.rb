# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::Poll do
  describe 'associations' do
    it { is_expected.to belong_to(:message).class_name('InternalChat::Message') }
    it { is_expected.to have_many(:options).class_name('InternalChat::PollOption').dependent(:destroy) }
    it { is_expected.to have_many(:votes).through(:options) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:question) }
  end

  describe '#expired?' do
    it 'returns false when expires_at is nil' do
      poll = build(:internal_chat_poll, expires_at: nil)
      expect(poll.expired?).to be false
    end

    it 'returns false when expires_at is in the future' do
      poll = build(:internal_chat_poll, expires_at: 1.hour.from_now)
      expect(poll.expired?).to be false
    end

    it 'returns true when expires_at is in the past' do
      poll = build(:internal_chat_poll, expires_at: 1.hour.ago)
      expect(poll.expired?).to be true
    end

    it 'returns false at the exact boundary (expires_at == current time)' do
      freeze_time do
        poll = build(:internal_chat_poll, expires_at: Time.current)
        expect(poll.expired?).to be false
      end
    end
  end

  describe '#total_votes_count' do
    it 'returns the total number of votes across all options' do
      poll = create(:internal_chat_poll)
      option1 = create(:internal_chat_poll_option, poll: poll)
      option2 = create(:internal_chat_poll_option, poll: poll)
      create(:internal_chat_poll_vote, option: option1)
      create(:internal_chat_poll_vote, option: option2)

      expect(poll.total_votes_count).to eq(2)
    end

    it 'returns 0 when there are no votes' do
      poll = create(:internal_chat_poll)
      create(:internal_chat_poll_option, poll: poll)

      expect(poll.total_votes_count).to eq(0)
    end

    it 'counts multiple votes on the same option' do
      poll = create(:internal_chat_poll)
      option = create(:internal_chat_poll_option, poll: poll)
      create(:internal_chat_poll_vote, option: option)
      create(:internal_chat_poll_vote, option: option)

      expect(poll.total_votes_count).to eq(2)
    end
  end

  describe 'default attribute values' do
    it 'defaults multiple_choice to false' do
      poll = build(:internal_chat_poll)
      expect(poll.multiple_choice).to be false
    end

    it 'defaults public_results to true' do
      poll = build(:internal_chat_poll)
      expect(poll.public_results).to be true
    end

    it 'defaults allow_revote to true' do
      poll = build(:internal_chat_poll)
      expect(poll.allow_revote).to be true
    end
  end
end
