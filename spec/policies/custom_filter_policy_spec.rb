# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomFilterPolicy, type: :policy do
  subject(:custom_filter_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }

  let(:administrator_context) do
    { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: agent.account_users.find_by(account: account) }
  end
  let(:other_agent_context) do
    { user: other_agent, account: account, account_user: other_agent.account_users.find_by(account: account) }
  end

  permissions :index?, :create? do
    it { expect(custom_filter_policy).to permit(administrator_context, build(:custom_filter)) }
    it { expect(custom_filter_policy).to permit(agent_context, build(:custom_filter)) }
  end

  permissions :show?, :update?, :destroy? do
    context 'when record is global' do
      let(:global_filter) { create(:custom_filter, account: account, user: administrator, visibility: :global) }

      it 'permits the author admin' do
        expect(custom_filter_policy).to permit(administrator_context, global_filter)
      end

      it 'permits another admin (handled via update? branch for non-author)' do
        another_admin = create(:user, :administrator, account: account)
        another_admin_context = { user: another_admin, account: account,
                                  account_user: another_admin.account_users.find_by(account: account) }
        expect(custom_filter_policy).to permit(another_admin_context, global_filter)
      end

      it 'permits show for agents but not destructive actions' do
        expect(custom_filter_policy.new(agent_context, global_filter).show?).to be true
        expect(custom_filter_policy.new(agent_context, global_filter).update?).to be false
        expect(custom_filter_policy.new(agent_context, global_filter).destroy?).to be false
      end

      it 'denies destructive actions to a non-admin author of a global filter' do
        agent_authored = create(:custom_filter, account: account, user: agent, visibility: :global)
        expect(custom_filter_policy.new(agent_context, agent_authored).update?).to be false
        expect(custom_filter_policy.new(agent_context, agent_authored).destroy?).to be false
      end
    end

    context 'when record is personal' do
      let(:personal_filter) { create(:custom_filter, account: account, user: agent, visibility: :personal) }

      it 'permits the author' do
        expect(custom_filter_policy).to permit(agent_context, personal_filter)
      end

      it 'denies non-authors, including admins' do
        expect(custom_filter_policy.new(other_agent_context, personal_filter).show?).to be false
        expect(custom_filter_policy.new(administrator_context, personal_filter).update?).to be false
        expect(custom_filter_policy.new(administrator_context, personal_filter).destroy?).to be false
      end
    end
  end
end
