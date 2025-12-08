# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::TaskAutoAssignmentService do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account, settings: { 'auto_assign_task_to_agent' => true }) }
  let!(:board_step) { create(:kanban_board_step, board: board) }
  let(:agent1) { create(:user, account: account) }
  let(:agent2) { create(:user, account: account) }
  let(:creator) { create(:user, account: account) }

  before do
    create(:kanban_board_agent, board: board, agent: agent1)
    create(:kanban_board_agent, board: board, agent: agent2)
  end

  describe '#perform' do
    context 'when auto_assign_task_to_agent is enabled' do
      context 'when task has no assigned agents' do
        let(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: creator) }

        it 'assigns an online agent to the task' do
          # Simulate agent1 being online
          allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
            { agent1.id.to_s => 'online' }
          )

          described_class.new(task: task).perform

          expect(task.reload.assigned_agents).to include(agent1)
        end

        it 'dispatches kanban_task_updated event when agent is assigned' do
          allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
            { agent1.id.to_s => 'online' }
          )

          expect(Rails.configuration.dispatcher).to receive(:dispatch)
            .with(Events::Types::KANBAN_TASK_UPDATED, anything, hash_including(task: task))

          described_class.new(task: task).perform
        end

        it 'does not assign when no agents are online' do
          allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})

          described_class.new(task: task).perform

          expect(task.reload.assigned_agents).to be_empty
        end

        it 'does not assign agents who are not online' do
          # agent1 is busy, agent2 is offline
          allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
            { agent1.id.to_s => 'busy' }
          )

          described_class.new(task: task).perform

          expect(task.reload.assigned_agents).to be_empty
        end

        it 'performs load-balancing across online agents' do
          allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
            { agent1.id.to_s => 'online', agent2.id.to_s => 'online' }
          )

          task1 = create(:kanban_task, board: board, board_step: board_step, account: account, creator: creator)
          task2 = create(:kanban_task, board: board, board_step: board_step, account: account, creator: creator)

          described_class.new(task: task1).perform
          described_class.new(task: task2).perform

          assigned_agents = [task1.reload.assigned_agents.first, task2.reload.assigned_agents.first]
          expect(assigned_agents).to contain_exactly(agent1, agent2)
        end
      end

      context 'when task already has assigned agents' do
        let(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: creator) }

        before do
          task.assigned_agents << agent1
        end

        it 'does not assign additional agents' do
          allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
            { agent2.id.to_s => 'online' }
          )

          expect do
            described_class.new(task: task).perform
          end.not_to(change { task.reload.assigned_agents.count })
        end
      end
    end

    context 'when auto_assign_task_to_agent is disabled' do
      let(:board) { create(:kanban_board, account: account, settings: { 'auto_assign_task_to_agent' => false }) }
      let(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: creator) }

      it 'does not assign any agent' do
        allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
          { agent1.id.to_s => 'online' }
        )

        described_class.new(task: task).perform

        expect(task.reload.assigned_agents).to be_empty
      end
    end
  end

  describe '#find_assignee' do
    let(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: creator) }

    it 'returns an available online agent' do
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
        { agent1.id.to_s => 'online' }
      )

      assignee = described_class.new(task: task).find_assignee

      expect(assignee).to eq(agent1)
    end

    it 'returns nil when no online agents are available' do
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})

      assignee = described_class.new(task: task).find_assignee

      expect(assignee).to be_nil
    end
  end
end
