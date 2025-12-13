# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::BoardPolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:admin_context) { { user: admin, account: account, account_user: account.account_users.find_by!(user: admin) } }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.find_by!(user: agent) } }

  before do
    account.enable_features('kanban')
    create(:kanban_board_agent, board: board, agent: agent)
  end

  permissions :index? do
    it { expect(policy).to permit(agent_context, board) }
  end

  permissions :create?, :update? do
    it 'allows administrators' do
      expect(policy).to permit(admin_context, board)
    end

    it 'denies agents' do
      expect(policy).not_to permit(agent_context, board)
    end
  end

  describe 'scope' do
    let!(:other_board) { create(:kanban_board, account: account) }

    it 'returns boards assigned to the agent' do
      scoped = described_class::Scope.new(agent_context, FazerAi::Kanban::Board).resolve

      expect(scoped).to include(board)
      expect(scoped).not_to include(other_board)
    end
  end
end
