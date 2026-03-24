# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::MentionService do
  let(:account) { create(:account) }
  let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

  describe '#perform' do
    it 'extracts mentioned user IDs from content' do
      sender = create(:user, account: account, role: :agent)
      user1 = create(:user, account: account, role: :agent)
      user2 = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://user/#{user1.id}/User1) and (mention://user/#{user2.id}/User2)"
      )

      result = described_class.new(message: message).perform

      expect(result).to contain_exactly(user1.id.to_s, user2.id.to_s)
    end

    it 'excludes the sender from mentioned user IDs' do
      sender = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "I mentioned myself (mention://user/#{sender.id}/Me)"
      )

      result = described_class.new(message: message).perform

      expect(result).to be_empty
    end

    it 'resolves @all to all channel members when sender is admin' do
      admin = create(:user, account: account, role: :administrator)
      member1 = create(:user, account: account, role: :agent)
      member2 = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: admin)
      create(:internal_chat_channel_member, channel: channel, user: member1)
      create(:internal_chat_channel_member, channel: channel, user: member2)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: admin,
                                content: '@all please review this'
      )

      result = described_class.new(message: message).perform

      expect(result).to contain_exactly(member1.id.to_s, member2.id.to_s)
      expect(result).not_to include(admin.id.to_s)
    end

    it 'ignores @all when sender is not admin' do
      agent = create(:user, account: account, role: :agent)
      member = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: agent)
      create(:internal_chat_channel_member, channel: channel, user: member)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: agent,
                                content: '@all please review this'
      )

      result = described_class.new(message: message).perform

      expect(result).to be_empty
    end

    it 'filters out invalid user IDs' do
      sender = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: 'Hey (mention://user/999999999/Ghost)'
      )

      result = described_class.new(message: message).perform

      expect(result).to be_empty
    end

    it 'returns nil when content is blank' do
      sender = create(:user, account: account, role: :agent)
      # Create message with attachments to bypass content presence validation
      message = build(:internal_chat_message, account: account, channel: channel, sender: sender, content: nil)
      allow(message).to receive(:content).and_return(nil)

      result = described_class.new(message: message).perform

      expect(result).to be_nil
    end

    it 'resolves @all for channel admin (not account admin)' do
      agent = create(:user, account: account, role: :agent)
      member = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: agent, role: :admin)
      create(:internal_chat_channel_member, channel: channel, user: member)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: agent,
                                content: '@all attention'
      )

      result = described_class.new(message: message).perform

      expect(result).to contain_exactly(member.id.to_s)
    end

    it 'deduplicates multiple mentions of the same user' do
      sender = create(:user, account: account, role: :agent)
      user1 = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://user/#{user1.id}/User1) and again (mention://user/#{user1.id}/User1)"
      )

      result = described_class.new(message: message).perform

      expect(result).to contain_exactly(user1.id.to_s)
    end

    it 'returns empty array when content has no mentions' do
      sender = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: 'Just a regular message with no mentions'
      )

      result = described_class.new(message: message).perform

      expect(result).to be_empty
    end

    it 'expands team mentions to team member user IDs' do
      sender = create(:user, account: account, role: :agent)
      member1 = create(:user, account: account, role: :agent)
      member2 = create(:user, account: account, role: :agent)
      team = create(:team, account: account)
      create(:team_member, user: member1, team: team)
      create(:team_member, user: member2, team: team)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://team/#{team.id}/#{team.name}) please review"
      )

      result = described_class.new(message: message).perform

      expect(result).to contain_exactly(member1.id.to_s, member2.id.to_s)
    end

    it 'deduplicates when user is mentioned directly and via team' do
      sender = create(:user, account: account, role: :agent)
      user1 = create(:user, account: account, role: :agent)
      user2 = create(:user, account: account, role: :agent)
      team = create(:team, account: account)
      create(:team_member, user: user1, team: team)
      create(:team_member, user: user2, team: team)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://user/#{user1.id}/User1) and (mention://team/#{team.id}/#{team.name})"
      )

      result = described_class.new(message: message).perform

      expect(result).to contain_exactly(user1.id.to_s, user2.id.to_s)
    end

    it 'excludes sender from team mention expansion' do
      sender = create(:user, account: account, role: :agent)
      member = create(:user, account: account, role: :agent)
      team = create(:team, account: account)
      create(:team_member, user: sender, team: team)
      create(:team_member, user: member, team: team)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://team/#{team.id}/#{team.name})"
      )

      result = described_class.new(message: message).perform

      expect(result).to contain_exactly(member.id.to_s)
      expect(result).not_to include(sender.id.to_s)
    end

    it 'returns empty for empty team mentions' do
      sender = create(:user, account: account, role: :agent)
      empty_team = create(:team, account: account)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://team/#{empty_team.id}/#{empty_team.name})"
      )

      result = described_class.new(message: message).perform

      expect(result).to be_empty
    end

    it 'ignores team mentions from other accounts' do
      sender = create(:user, account: account, role: :agent)
      other_account = create(:account)
      other_team = create(:team, account: other_account)
      other_user = create(:user, account: other_account, role: :agent)
      create(:team_member, user: other_user, team: other_team)
      create(:internal_chat_channel_member, channel: channel, user: sender)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: sender,
                                content: "Hey (mention://team/#{other_team.id}/OtherTeam)"
      )

      result = described_class.new(message: message).perform

      expect(result).to be_empty
    end

    it 'handles mixed @all and individual mentions for admin sender' do
      admin = create(:user, account: account, role: :administrator)
      member1 = create(:user, account: account, role: :agent)
      member2 = create(:user, account: account, role: :agent)
      create(:internal_chat_channel_member, channel: channel, user: admin)
      create(:internal_chat_channel_member, channel: channel, user: member1)
      create(:internal_chat_channel_member, channel: channel, user: member2)

      message = create(
        :internal_chat_message, account: account, channel: channel, sender: admin,
                                content: "@all and (mention://user/#{member1.id}/Member1)"
      )

      result = described_class.new(message: message).perform

      # @all overrides, includes all channel members except sender
      expect(result).to contain_exactly(member1.id.to_s, member2.id.to_s)
    end
  end
end
