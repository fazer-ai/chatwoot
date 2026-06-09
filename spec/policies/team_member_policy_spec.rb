# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamMemberPolicy, type: :policy do
  subject(:team_member_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account_id: account.id) } }
  let(:manager_context) { { user: manager, account: account, account_user: manager.account_users.find_by(account_id: account.id) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account_id: account.id) } }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:manager) { create(:user, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:team) { create(:team, account: account) }

  before do
    manager.account_users.find_by(account_id: account.id).update!(role: :manager)
  end

  permissions :create?, :update?, :destroy? do
    it { expect(team_member_policy).to permit(administrator_context, team) }
    it { expect(team_member_policy).to permit(manager_context, team) }
    it { expect(team_member_policy).not_to permit(agent_context, team) }
  end
end
