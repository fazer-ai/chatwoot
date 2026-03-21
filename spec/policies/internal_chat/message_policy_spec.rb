require 'rails_helper'

RSpec.describe InternalChat::MessagePolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }
  let(:other_agent_context) { { user: other_agent, account: account, account_user: other_agent.account_users.find_by(account: account) } }

  permissions :index?, :create? do
    context 'when channel is public' do
      let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }
      let(:message) { create(:internal_chat_message, account: account, channel: channel, sender: agent) }

      it 'allows any agent' do
        expect(subject).to permit(agent_context, message)
      end

      it 'allows administrator' do
        expect(subject).to permit(administrator_context, message)
      end
    end

    context 'when channel is private' do
      let(:channel) { create(:internal_chat_channel, :private_channel, account: account) }
      let(:message) { create(:internal_chat_message, account: account, channel: channel, sender: agent) }

      context 'when user is a member' do
        before { create(:internal_chat_channel_member, channel: channel, user: agent) }

        it 'allows access' do
          expect(subject).to permit(agent_context, message)
        end
      end

      context 'when user is not a member' do
        it 'denies access' do
          expect(subject).not_to permit(other_agent_context, message)
        end
      end

      context 'when user is an administrator (not a member)' do
        it 'allows access' do
          expect(subject).to permit(administrator_context, message)
        end
      end
    end
  end

  permissions :update?, :destroy? do
    let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }
    let(:message) { create(:internal_chat_message, account: account, channel: channel, sender: agent) }

    context 'when user is the sender' do
      it 'allows access' do
        expect(subject).to permit(agent_context, message)
      end
    end

    context 'when user is an administrator' do
      it 'allows access' do
        expect(subject).to permit(administrator_context, message)
      end
    end

    context 'when user is not the sender and not an admin' do
      it 'denies access' do
        expect(subject).not_to permit(other_agent_context, message)
      end
    end
  end

  permissions :pin?, :unpin? do
    let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }
    let(:message) { create(:internal_chat_message, account: account, channel: channel, sender: other_agent) }

    context 'when user is an administrator' do
      it 'allows access' do
        expect(subject).to permit(administrator_context, message)
      end
    end

    context 'when user is a channel admin' do
      before { create(:internal_chat_channel_member, channel: channel, user: agent, role: :admin) }

      it 'allows access' do
        expect(subject).to permit(agent_context, message)
      end
    end

    context 'when user is a regular member' do
      before { create(:internal_chat_channel_member, channel: channel, user: agent, role: :member) }

      it 'denies access' do
        expect(subject).not_to permit(agent_context, message)
      end
    end
  end

  permissions :thread? do
    context 'when channel is public' do
      let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }
      let(:message) { create(:internal_chat_message, account: account, channel: channel, sender: agent) }

      it 'allows any agent' do
        expect(subject).to permit(other_agent_context, message)
      end
    end
  end
end
