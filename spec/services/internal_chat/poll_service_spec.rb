# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::PollService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:channel) { create(:internal_chat_channel, account: account) }
  let(:message) { create(:internal_chat_message, :poll, account: account, channel: channel, sender: user) }
  let(:poll) { create(:internal_chat_poll, message: message) }
  let(:option) { create(:internal_chat_poll_option, poll: poll) }

  describe '#vote' do
    it 'creates a vote and reloads the poll' do
      service = described_class.new(poll: poll, user: user, option: option)
      service.vote

      expect(option.votes.where(user: user)).to exist
    end

    it 'raises an error when the poll has expired' do
      poll.update!(expires_at: 1.hour.ago)
      service = described_class.new(poll: poll, user: user, option: option)

      expect { service.vote }.to raise_error(StandardError, 'Poll has expired')
    end

    it 'raises an error when revoting is not allowed and user already voted' do
      poll.update!(allow_revote: false)
      create(:internal_chat_poll_vote, option: option, user: user)
      service = described_class.new(poll: poll, user: user, option: option)

      expect { service.vote }.to raise_error(StandardError, 'Revoting is not allowed')
    end

    it 'destroys old vote and creates new one when revoting is allowed on single-choice poll' do
      poll.update!(allow_revote: true, multiple_choice: false)
      option2 = create(:internal_chat_poll_option, poll: poll)
      create(:internal_chat_poll_vote, option: option, user: user)

      service = described_class.new(poll: poll, user: user, option: option2)
      service.vote

      expect(InternalChat::PollVote.where(user: user).count).to eq(1)
      expect(InternalChat::PollVote.find_by(user: user).option).to eq(option2)
    end

    it 'keeps existing votes on multiple-choice poll when revoting' do
      poll.update!(allow_revote: true, multiple_choice: true)
      option2 = create(:internal_chat_poll_option, poll: poll)
      create(:internal_chat_poll_vote, option: option, user: user)

      service = described_class.new(poll: poll, user: user, option: option2)
      service.vote

      expect(InternalChat::PollVote.where(user: user).count).to eq(2)
    end
  end

  describe '#unvote' do
    it 'destroys the vote and reloads the poll' do
      create(:internal_chat_poll_vote, option: option, user: user)
      service = described_class.new(poll: poll, user: user, option: option)
      service.unvote

      expect(option.votes.where(user: user)).not_to exist
    end

    it 'raises an error when there is no existing vote' do
      service = described_class.new(poll: poll, user: user, option: option)

      expect { service.unvote }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'raises an error when the poll has expired' do
      poll.update!(expires_at: 1.hour.ago)
      create(:internal_chat_poll_vote, option: option, user: user)
      service = described_class.new(poll: poll, user: user, option: option)

      expect { service.unvote }.to raise_error(StandardError, 'Poll has expired')
    end
  end

  describe 'option validation' do
    it 'raises ArgumentError when option does not belong to the poll' do
      other_poll = create(:internal_chat_poll)
      other_option = create(:internal_chat_poll_option, poll: other_poll)

      service = described_class.new(poll: poll, user: user, option: other_option)

      expect { service.vote }.to raise_error(ArgumentError, 'Option does not belong to this poll')
    end

    it 'raises ArgumentError on unvote when option does not belong to the poll' do
      other_poll = create(:internal_chat_poll)
      other_option = create(:internal_chat_poll_option, poll: other_poll)

      service = described_class.new(poll: poll, user: user, option: other_option)

      expect { service.unvote }.to raise_error(ArgumentError, 'Option does not belong to this poll')
    end
  end

  describe 'idempotency' do
    it 'raises duplicate vote error when voting for the same option on multi-choice poll' do
      create(:internal_chat_poll_vote, option: option, user: user)
      poll.update!(allow_revote: true, multiple_choice: true)

      service = described_class.new(poll: poll, user: user, option: option)

      expect { service.vote }.to raise_error(StandardError, 'Already voted for this option')
    end
  end
end
