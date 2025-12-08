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

  describe '#auto_assign_agent_to_conversations' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee_id: nil) }

    before do
      task.conversation_ids = [conversation.id]
      task.save!
    end

    context 'when auto_assign_agent_to_conversation is enabled' do
      before { board.update!(settings: { 'auto_assign_agent_to_conversation' => true }) }

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

    context 'when auto_assign_agent_to_conversation is disabled' do
      before { board.update!(settings: { 'auto_assign_agent_to_conversation' => false }) }

      it 'does not assign agents to conversations' do
        create(:kanban_task_agent, task: task, agent: agent)

        expect(conversation.reload.assignee_id).to be_nil
      end
    end

    context 'when auto_assign_agent_to_conversation setting is not present' do
      before { board.update!(settings: {}) }

      it 'does not assign agents to conversations' do
        create(:kanban_task_agent, task: task, agent: agent)

        expect(conversation.reload.assignee_id).to be_nil
      end
    end
  end
end
