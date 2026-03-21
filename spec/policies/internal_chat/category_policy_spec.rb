require 'rails_helper'

RSpec.describe InternalChat::CategoryPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:category) { create(:internal_chat_category, account: account) }

  permissions :index? do
    context 'when user is an administrator' do
      it 'allows index' do
        expect(subject).to permit(administrator_context, category)
      end
    end

    context 'when user is an agent' do
      it 'allows index' do
        expect(subject).to permit(agent_context, category)
      end
    end
  end

  permissions :create? do
    context 'when user is an administrator' do
      it 'allows create' do
        expect(subject).to permit(administrator_context, category)
      end
    end

    context 'when user is an agent' do
      it 'denies create' do
        expect(subject).not_to permit(agent_context, category)
      end
    end
  end

  permissions :update? do
    context 'when user is an administrator' do
      it 'allows update' do
        expect(subject).to permit(administrator_context, category)
      end
    end

    context 'when user is an agent' do
      it 'denies update' do
        expect(subject).not_to permit(agent_context, category)
      end
    end
  end

  permissions :destroy? do
    context 'when user is an administrator' do
      it 'allows destroy' do
        expect(subject).to permit(administrator_context, category)
      end
    end

    context 'when user is an agent' do
      it 'denies destroy' do
        expect(subject).not_to permit(agent_context, category)
      end
    end
  end
end
