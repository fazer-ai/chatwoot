# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::TaskAgent, type: :model do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:board_step) { create(:kanban_board_step, board: board) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:task) { create(:kanban_task, board: board, board_step: board_step, account: account, creator: create(:user, account: account)) }

  before do
    create(:kanban_board_inbox, board: board, inbox: inbox)
    create(:kanban_board_agent, board: board, agent: agent)
  end

  describe 'validations' do
    it { is_expected.to belong_to(:task) }
    it { is_expected.to belong_to(:agent) }

    it 'validates uniqueness of task_id scoped to agent_id' do
      create(:kanban_task_agent, task: task, agent: agent)
      duplicate = build(:kanban_task_agent, task: task, agent: agent)
      expect(duplicate).not_to be_valid
    end
  end

  describe '#sync_agent_to_conversations' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee_id: nil) }

    before do
      task.conversation_ids = [conversation.display_id]
      task.save!
    end

    context 'when sync_task_and_conversation_agents is enabled' do
      before { board.update!(settings: { 'sync_task_and_conversation_agents' => true }) }

      it 'assigns the agent to unassigned conversations when agent is assignable' do
        create(:inbox_member, inbox: inbox, user: agent)
        create(:kanban_task_agent, task: task, agent: agent)

        expect(conversation.reload.assignee_id).to eq(agent.id)
      end

      it 'does not assign the agent when agent is not assignable to the inbox' do
        create(:kanban_task_agent, task: task, agent: agent)

        expect(conversation.reload.assignee_id).to be_nil
      end

      it 'does not change already assigned conversations' do
        other_agent = create(:user, account: account)
        conversation.update!(assignee_id: other_agent.id)

        create(:inbox_member, inbox: inbox, user: agent)
        create(:kanban_task_agent, task: task, agent: agent)

        expect(conversation.reload.assignee_id).to eq(other_agent.id)
      end
    end

    context 'when sync_task_and_conversation_agents is disabled' do
      before { board.update!(settings: { 'sync_task_and_conversation_agents' => false }) }

      it 'does not assign agents to conversations' do
        create(:kanban_task_agent, task: task, agent: agent)

        expect(conversation.reload.assignee_id).to be_nil
      end
    end

    context 'when sync_task_and_conversation_agents setting is not present' do
      before { board.update!(settings: {}) }

      it 'does not assign agents to conversations' do
        create(:kanban_task_agent, task: task, agent: agent)

        expect(conversation.reload.assignee_id).to be_nil
      end
    end
  end

  describe '#unassign_agent_from_conversations' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee_id: agent.id) }

    before do
      create(:inbox_member, inbox: inbox, user: agent)
      task.conversation_ids = [conversation.display_id]
      task.save!
    end

    context 'when sync_task_and_conversation_agents is enabled' do
      before { board.update!(settings: { 'sync_task_and_conversation_agents' => true }) }

      it 'unassigns the agent from conversations when task agent is destroyed' do
        task_agent = create(:kanban_task_agent, task: task, agent: agent)
        task_agent.destroy!

        expect(conversation.reload.assignee_id).to be_nil
      end

      it 'unassigns the agent from conversations when using assigned_agent_ids=' do
        task.assigned_agent_ids = [agent.id]
        task.save!

        expect(task.reload.assigned_agents).to include(agent)

        task.assigned_agent_ids = []
        task.save!

        expect(conversation.reload.assignee_id).to be_nil
      end

      it 'does not unassign other agents from conversations' do
        other_agent = create(:user, account: account)
        conversation.update!(assignee_id: other_agent.id)

        task_agent = create(:kanban_task_agent, task: task, agent: agent)
        task_agent.destroy!

        expect(conversation.reload.assignee_id).to eq(other_agent.id)
      end

      it 'reassigns conversation to next available task agent when current assignee is removed' do
        other_agent = create(:user, account: account)
        create(:inbox_member, inbox: conversation.inbox, user: other_agent)

        create(:kanban_task_agent, task: task, agent: agent)
        create(:kanban_task_agent, task: task, agent: other_agent)

        expect(conversation.reload.assignee_id).to eq(agent.id)

        task.task_agents.find_by(agent_id: agent.id).destroy!

        expect(conversation.reload.assignee_id).to eq(other_agent.id)
      end
    end

    context 'when sync_task_and_conversation_agents is disabled' do
      before { board.update!(settings: { 'sync_task_and_conversation_agents' => false }) }

      it 'does not unassign agents from conversations' do
        task_agent = create(:kanban_task_agent, task: task, agent: agent)
        task_agent.destroy!

        expect(conversation.reload.assignee_id).to eq(agent.id)
      end
    end
  end
end
