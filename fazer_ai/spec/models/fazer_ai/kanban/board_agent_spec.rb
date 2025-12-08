# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::BoardAgent, type: :model do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }

  describe 'validations' do
    subject { create(:kanban_board_agent, board: board, agent: create(:user, account: account)) }

    it { is_expected.to validate_uniqueness_of(:agent_id).scoped_to(:board_id) }

    it 'requires the agent to belong to the same account as the board' do
      agent = build(:kanban_board_agent, board: board, agent: create(:user))

      expect(agent).not_to be_valid
      expect(agent.errors[:agent_id]).to include(I18n.t('kanban.agents.errors.invalid_agent'))
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:board) }
    it { is_expected.to belong_to(:agent) }
  end

  describe 'callbacks' do
    let(:agent) { create(:user, account: account) }
    let!(:board_agent) { create(:kanban_board_agent, board: board, agent: agent) }
    let(:task) { create(:kanban_task, board: board) }

    before do
      task.assigned_agents << agent
    end

    it 'unassigns the agent from board tasks when removed from board' do
      expect { board_agent.destroy }.to change { task.reload.assigned_agents.count }.by(-1)
    end
  end
end
