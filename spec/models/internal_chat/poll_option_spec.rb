# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::PollOption do
  describe 'associations' do
    it { is_expected.to belong_to(:poll).class_name('InternalChat::Poll') }
    it { is_expected.to have_many(:votes).class_name('InternalChat::PollVote').dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:text) }
  end

  describe 'scopes' do
    describe '.ordered' do
      it 'returns options ordered by position ascending' do
        poll = create(:internal_chat_poll)
        option3 = create(:internal_chat_poll_option, poll: poll, position: 3)
        option1 = create(:internal_chat_poll_option, poll: poll, position: 1)
        option2 = create(:internal_chat_poll_option, poll: poll, position: 2)

        expect(poll.options.ordered).to eq([option1, option2, option3])
      end
    end
  end

  describe '#votes_count' do
    it 'returns the number of votes for this option' do
      option = create(:internal_chat_poll_option)
      create(:internal_chat_poll_vote, option: option)
      create(:internal_chat_poll_vote, option: option)

      expect(option.votes_count).to eq(2)
    end

    it 'returns 0 when there are no votes' do
      option = create(:internal_chat_poll_option)

      expect(option.votes_count).to eq(0)
    end
  end
end
