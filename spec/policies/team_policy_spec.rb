# frozen_string_literal: true

require 'rails_helper'

# Rubocop's RepeatedExample treats every `permissions :x do` as part of the
# same example group, so identical `it` lines across permissions blocks get
# flagged even though they target different policy methods.
# rubocop:disable RSpec/RepeatedExample
RSpec.describe TeamPolicy, type: :policy do
  subject(:team_policy) { described_class }

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

  permissions :update? do
    it { expect(team_policy).to permit(administrator_context, team) }
    it { expect(team_policy).to permit(manager_context, team) }
    it { expect(team_policy).not_to permit(agent_context, team) }
  end

  permissions :create?, :destroy? do
    it { expect(team_policy).to permit(administrator_context, team) }
    it { expect(team_policy).not_to permit(manager_context, team) }
    it { expect(team_policy).not_to permit(agent_context, team) }
  end
end
# rubocop:enable RSpec/RepeatedExample
