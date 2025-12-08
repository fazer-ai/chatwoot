# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::AutomationRules::KanbanActionService do
  subject(:service) { described_class.new(automation_rule, account, task) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:board_inbox) { create(:kanban_board_inbox, board: board, inbox: inbox) } # rubocop:disable RSpec/LetSetup
  let!(:step1) { create(:kanban_board_step, board: board) }
  let!(:step2) { create(:kanban_board_step, board: board) }
  let!(:completed_step) { create(:kanban_board_step, board: board) }
  let(:task) { create(:kanban_task, account: account, board: board, board_step: step1, conversation_ids: [conversation.id]) }
  let(:agent) { create(:user, account: account) }
  let!(:board_agent) { create(:kanban_board_agent, board: board, agent: agent) } # rubocop:disable RSpec/LetSetup
  let!(:inbox_member) { create(:inbox_member, inbox: inbox, user: agent) } # rubocop:disable RSpec/LetSetup

  let(:automation_rule) do
    create(:automation_rule,
           account: account,
           event_name: 'kanban_task_created',
           conditions: [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id] }],
           actions: [])
  end

  describe '#assign_agent' do
    before do
      automation_rule.update!(actions: [{ action_name: 'assign_agent', action_params: [agent.id] }])
    end

    it 'assigns agent to the task' do
      service.perform
      expect(task.reload.assigned_agents).to include(agent)
    end

    it 'assigns agent to the linked conversation' do
      service.perform
      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    context 'when agent_id is nil' do
      before do
        task.task_agents.create!(agent: agent)
        automation_rule.update!(actions: [{ action_name: 'assign_agent', action_params: ['nil'] }])
      end

      it 'unassigns all agents from the task' do
        service.perform
        expect(task.reload.assigned_agents).to be_empty
      end
    end

    context 'when agent does not belong to board' do
      let(:other_agent) { create(:user, account: account) }

      before do
        automation_rule.update!(actions: [{ action_name: 'assign_agent', action_params: [other_agent.id] }])
      end

      it 'does not assign the agent' do
        service.perform
        expect(task.reload.assigned_agents).not_to include(other_agent)
      end
    end
  end

  describe '#move_to_step' do
    before do
      automation_rule.update!(actions: [{ action_name: 'move_to_step', action_params: [step2.id] }])
    end

    it 'moves task to the specified step' do
      service.perform
      expect(task.reload.board_step_id).to eq(step2.id)
    end

    context 'when step does not exist' do
      before do
        automation_rule.update!(actions: [{ action_name: 'move_to_step', action_params: [99_999] }])
      end

      it 'does not move the task' do
        service.perform
        expect(task.reload.board_step_id).to eq(step1.id)
      end
    end
  end

  describe '#mark_completed' do
    before do
      # Ensure completed_step is the last step (completed)
      board.update!(steps_order: [step1.id, step2.id, completed_step.id])
      automation_rule.update!(actions: [{ action_name: 'mark_completed', action_params: [] }])
    end

    it 'moves task to the completed step' do
      service.perform
      expect(task.reload.board_step_id).to eq(completed_step.id)
    end
  end

  describe '#change_priority' do
    before do
      automation_rule.update!(actions: [{ action_name: 'change_priority', action_params: ['urgent'] }])
    end

    it 'changes task priority' do
      service.perform
      expect(task.reload.priority).to eq('urgent')
    end

    context 'when priority is invalid' do
      before do
        automation_rule.update!(actions: [{ action_name: 'change_priority', action_params: ['invalid'] }])
      end

      it 'does not change priority' do
        original_priority = task.priority
        service.perform
        expect(task.reload.priority).to eq(original_priority)
      end
    end
  end

  describe '#send_webhook_event' do
    before do
      automation_rule.update!(actions: [{ action_name: 'send_webhook_event', action_params: ['https://example.com/webhook'] }])
    end

    it 'enqueues a webhook job' do
      expect do
        service.perform
      end.to have_enqueued_job(WebhookJob)
    end
  end

  describe '#send_message' do
    before do
      automation_rule.update!(actions: [{ action_name: 'send_message', action_params: ['Hello from automation'] }])
    end

    it 'sends a message to linked conversations' do
      expect do
        service.perform
      end.to change(conversation.messages, :count).by(1)
    end

    it 'creates a public message' do
      service.perform
      message = conversation.messages.last
      expect(message.private).to be(false)
      expect(message.content).to eq('Hello from automation')
    end
  end

  describe '#add_private_note' do
    before do
      automation_rule.update!(actions: [{ action_name: 'add_private_note', action_params: ['Internal note'] }])
    end

    it 'adds a private note to linked conversations' do
      expect do
        service.perform
      end.to change(conversation.messages, :count).by(1)
    end

    it 'creates a private message' do
      service.perform
      message = conversation.messages.last
      expect(message.private).to be(true)
      expect(message.content).to eq('Internal note')
    end
  end
end
