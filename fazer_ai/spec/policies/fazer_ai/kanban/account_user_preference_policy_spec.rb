# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::AccountUserPreferencePolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:admin_context) { { user: admin, account: account, account_user: account.account_users.find_by!(user: admin) } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.find_by!(user: agent) } }
  let(:other_agent_context) { { user: other_agent, account: account, account_user: account.account_users.find_by!(user: other_agent) } }

  before do
    account.enable_features('kanban')
  end

  permissions :update? do
    context 'with new preference record' do
      it 'allows admin to create their own preference' do
        admin_account_user = account.account_users.find_by!(user: admin)
        new_preference = build(:kanban_account_user_preference, account_user: admin_account_user)

        expect(policy).to permit(admin_context, new_preference)
      end

      it 'allows agent to create their own preference' do
        agent_account_user = account.account_users.find_by!(user: agent)
        new_preference = build(:kanban_account_user_preference, account_user: agent_account_user)

        expect(policy).to permit(agent_context, new_preference)
      end
    end

    context 'with existing preference record' do
      it 'allows admin to update their own preference' do
        admin_account_user = account.account_users.find_by!(user: admin)
        preference = create(:kanban_account_user_preference, account_user: admin_account_user)

        expect(policy).to permit(admin_context, preference)
      end

      it 'allows agent to update their own preference' do
        agent_account_user = account.account_users.find_by!(user: agent)
        preference = create(:kanban_account_user_preference, account_user: agent_account_user)

        expect(policy).to permit(agent_context, preference)
      end

      it 'denies agent from updating another agent preference' do
        other_account_user = account.account_users.find_by!(user: other_agent)
        preference = create(:kanban_account_user_preference, account_user: other_account_user)

        expect(policy).not_to permit(agent_context, preference)
      end

      it 'denies admin from updating another user preference' do
        agent_account_user = account.account_users.find_by!(user: agent)
        preference = create(:kanban_account_user_preference, account_user: agent_account_user)

        expect(policy).not_to permit(admin_context, preference)
      end
    end

    context 'when feature is disabled' do
      before do
        account.disable_features('kanban')
      end

      it 'denies admin' do
        admin_account_user = account.account_users.find_by!(user: admin)
        preference = create(:kanban_account_user_preference, account_user: admin_account_user)

        expect(policy).not_to permit(admin_context, preference)
      end

      it 'denies agent' do
        agent_account_user = account.account_users.find_by!(user: agent)
        preference = create(:kanban_account_user_preference, account_user: agent_account_user)

        expect(policy).not_to permit(agent_context, preference)
      end
    end
  end
end
