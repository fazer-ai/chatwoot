# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::TaskPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:board_step) { create(:kanban_board_step, board: board) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:admin_context) { { user: admin, account: account, account_user: account.account_users.find_by!(user: admin) } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.find_by!(user: agent) } }
  let(:other_agent_context) { { user: other_agent, account: account, account_user: account.account_users.find_by!(user: other_agent) } }

  let(:task) do
    create(:kanban_task, board: board, board_step: board_step, account: account, assigned_agents: [agent], creator: agent)
  end

  before do
    account.enable_features('kanban')
    create(:kanban_board_agent, board: board, agent: agent)
  end

  permissions :create? do
    it 'allows an agent assigned to the board' do
      new_task = build(:kanban_task, board: board, account: account)

      expect(policy).to permit(agent_context, new_task)
    end

    it 'denies agents that are not assigned to the board' do
      new_task = build(:kanban_task, board: board, account: account)

      expect(policy).not_to permit(other_agent_context, new_task)
    end
  end

  permissions :update? do
    it 'allows administrators' do
      expect(policy).to permit(admin_context, task)
    end

    it 'allows assigned agents when they own the task' do
      expect(policy).to permit(agent_context, task)
    end

    it 'denies unassigned agents' do
      expect(policy).not_to permit(other_agent_context, task)
    end
  end

  describe 'scope' do
    let!(:visible_task) { task }
    let!(:hidden_task) do
      board = create(:kanban_board, account: account)
      board.assigned_agents << other_agent
      create(:kanban_task, board: board, account: account, assigned_agents: [other_agent], creator: other_agent)
    end

    before do
      hidden_task.board.board_agents.destroy_all
    end

    it 'returns tasks accessible to the agent' do
      scoped = described_class::Scope.new(agent_context, FazerAi::Kanban::Task).resolve

      expect(scoped).to include(visible_task)
      expect(scoped).not_to include(hidden_task)
    end
  end
end
