# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:other_user) { create(:user, account: account) }
  let(:channel) { create(:internal_chat_channel, account: account) }

  before do
    create(:internal_chat_channel_member, channel: channel, user: user)
    create(:internal_chat_channel_member, channel: channel, user: other_user)
  end

  describe 'messages' do
    let!(:user_message) { create(:internal_chat_message, channel: channel, sender: user, account: account) }
    let!(:other_message) { create(:internal_chat_message, channel: channel, sender: other_user, account: account) }

    it 'preserves messages but nullifies sender_id' do
      expect { user.destroy }.to change { user_message.reload.sender_id }.from(user.id).to(nil)
    end

    it 'does not delete the messages' do
      expect { user.destroy }.not_to change(InternalChat::Message, :count)
    end

    it 'does not affect other users messages' do
      user.destroy!
      expect(other_message.reload.sender_id).to eq(other_user.id)
    end
  end

  describe 'reactions' do
    let!(:message) { create(:internal_chat_message, channel: channel, sender: other_user, account: account) }
    let!(:user_reaction) { create(:internal_chat_reaction, message: message, user: user, emoji: '👍') }
    let!(:other_reaction) { create(:internal_chat_reaction, message: message, user: other_user, emoji: '👍') }

    it 'deletes reactions from the deleted user' do
      expect { user.destroy }.to change(InternalChat::Reaction, :count).by(-1)
      expect { user_reaction.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'does not affect other users reactions' do
      user.destroy!
      expect(other_reaction.reload).to be_present
    end
  end

  describe 'poll votes' do
    let!(:poll) { create(:internal_chat_poll) }
    let(:option) { create(:internal_chat_poll_option, poll: poll) }
    let!(:user_vote) { create(:internal_chat_poll_vote, option: option, user: user) }
    let!(:other_vote) { create(:internal_chat_poll_vote, option: option, user: other_user) }

    it 'deletes poll votes from the deleted user' do
      expect { user.destroy }.to change(InternalChat::PollVote, :count).by(-1)
      expect { user_vote.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'does not affect other users votes' do
      user.destroy!
      expect(other_vote.reload).to be_present
    end
  end

  describe 'channel memberships' do
    it 'removes channel memberships for the deleted user' do
      expect { user.destroy }.to change { InternalChat::ChannelMember.where(user_id: user.id).count }.to(0)
    end

    it 'does not remove other users memberships' do
      user.destroy!
      expect(InternalChat::ChannelMember.where(user: other_user)).to exist
    end

    it 'does not delete the channel' do
      expect { user.destroy }.not_to change(InternalChat::Channel, :count)
    end
  end
end
