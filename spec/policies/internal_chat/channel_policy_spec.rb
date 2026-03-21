require 'rails_helper'

RSpec.describe InternalChat::ChannelPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }
  let(:other_agent_context) { { user: other_agent, account: account, account_user: other_agent.account_users.find_by(account: account) } }

  permissions :index? do
    let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

    context 'when user is an administrator' do
      it 'allows index' do
        expect(subject).to permit(administrator_context, channel)
      end
    end

    context 'when user is an agent' do
      it 'allows index' do
        expect(subject).to permit(agent_context, channel)
      end
    end
  end

  permissions :show? do
    context 'when channel is public' do
      let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

      it 'allows any agent' do
        expect(subject).to permit(agent_context, channel)
      end

      it 'allows administrator' do
        expect(subject).to permit(administrator_context, channel)
      end
    end

    context 'when channel is private' do
      let(:channel) { create(:internal_chat_channel, :private_channel, account: account) }

      context 'when user is a member' do
        before { create(:internal_chat_channel_member, channel: channel, user: agent) }

        it 'allows access' do
          expect(subject).to permit(agent_context, channel)
        end
      end

      context 'when user is not a member' do
        it 'denies access' do
          expect(subject).not_to permit(other_agent_context, channel)
        end
      end

      context 'when user is an administrator (not a member)' do
        it 'allows access' do
          expect(subject).to permit(administrator_context, channel)
        end
      end
    end

    context 'when channel is a DM' do
      let(:channel) { create(:internal_chat_channel, :dm, account: account) }

      context 'when user is a member' do
        before { create(:internal_chat_channel_member, channel: channel, user: agent) }

        it 'allows access' do
          expect(subject).to permit(agent_context, channel)
        end
      end

      context 'when user is not a member' do
        it 'denies access' do
          expect(subject).not_to permit(other_agent_context, channel)
        end
      end
    end
  end

  permissions :create? do
    context 'when channel is a regular channel' do
      let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

      it 'allows administrator' do
        expect(subject).to permit(administrator_context, channel)
      end

      it 'denies agent' do
        expect(subject).not_to permit(agent_context, channel)
      end
    end

    context 'when channel is a DM' do
      let(:channel) { create(:internal_chat_channel, :dm, account: account) }

      it 'allows any agent' do
        expect(subject).to permit(agent_context, channel)
      end

      it 'allows administrator' do
        expect(subject).to permit(administrator_context, channel)
      end
    end
  end

  permissions :update? do
    let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

    context 'when user is an administrator' do
      it 'allows update' do
        expect(subject).to permit(administrator_context, channel)
      end
    end

    context 'when user is a channel admin' do
      before { create(:internal_chat_channel_member, channel: channel, user: agent, role: :admin) }

      it 'allows update' do
        expect(subject).to permit(agent_context, channel)
      end
    end

    context 'when user is a regular member' do
      before { create(:internal_chat_channel_member, channel: channel, user: agent, role: :member) }

      it 'denies update' do
        expect(subject).not_to permit(agent_context, channel)
      end
    end
  end

  permissions :destroy? do
    let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

    context 'when user is an administrator' do
      it 'allows destroy' do
        expect(subject).to permit(administrator_context, channel)
      end
    end

    context 'when user is an agent' do
      it 'denies destroy' do
        expect(subject).not_to permit(agent_context, channel)
      end
    end
  end

  permissions :archive? do
    let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

    context 'when user is an administrator' do
      it 'allows archive' do
        expect(subject).to permit(administrator_context, channel)
      end
    end

    context 'when user is an agent' do
      it 'denies archive' do
        expect(subject).not_to permit(agent_context, channel)
      end
    end
  end

  permissions :toggle_typing_status?, :mark_read?, :mark_unread? do
    context 'when channel is public' do
      let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

      it 'allows any agent' do
        expect(subject).to permit(agent_context, channel)
      end
    end

    context 'when channel is private' do
      let(:channel) { create(:internal_chat_channel, :private_channel, account: account) }

      context 'when user is a member' do
        before { create(:internal_chat_channel_member, channel: channel, user: agent) }

        it 'allows access' do
          expect(subject).to permit(agent_context, channel)
        end
      end

      context 'when user is not a member' do
        it 'denies access' do
          expect(subject).not_to permit(other_agent_context, channel)
        end
      end
    end
  end
end
