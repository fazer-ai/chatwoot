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
  let(:task) { create(:kanban_task, account: account, board: board, board_step: step1, conversation_ids: [conversation.display_id]) }
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
    let(:completed_step) { create(:kanban_board_step, board: board) }

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

  describe '#add_label_to_task' do
    before do
      automation_rule.update!(actions: [{ action_name: 'add_label_to_task', action_params: %w[priority bug] }])
    end

    it 'adds labels to the task' do
      service.perform
      expect(task.reload.label_list).to contain_exactly('priority', 'bug')
    end

    context 'when labels already exist' do
      before do
        task.update!(label_list: ['existing'])
      end

      it 'adds new labels while keeping existing ones' do
        service.perform
        expect(task.reload.label_list).to contain_exactly('existing', 'priority', 'bug')
      end
    end

    context 'when action_params is blank' do
      before do
        automation_rule.update!(actions: [{ action_name: 'add_label_to_task', action_params: [] }])
      end

      it 'does not change labels' do
        service.perform
        expect(task.reload.label_list).to be_empty
      end
    end
  end

  describe '#remove_label_from_task' do
    before do
      task.update!(label_list: %w[priority bug feature])
      automation_rule.update!(actions: [{ action_name: 'remove_label_from_task', action_params: %w[priority bug] }])
    end

    it 'removes specified labels from the task' do
      service.perform
      expect(task.reload.label_list).to contain_exactly('feature')
    end

    context 'when labels do not exist' do
      before do
        task.update!(label_list: ['other'])
        automation_rule.update!(actions: [{ action_name: 'remove_label_from_task', action_params: ['nonexistent'] }])
      end

      it 'does not change existing labels' do
        service.perform
        expect(task.reload.label_list).to contain_exactly('other')
      end
    end

    context 'when action_params is blank' do
      before do
        task.update!(label_list: ['existing'])
        automation_rule.update!(actions: [{ action_name: 'remove_label_from_task', action_params: [] }])
      end

      it 'does not change labels' do
        service.perform
        expect(task.reload.label_list).to contain_exactly('existing')
      end
    end
  end

  describe '#assign_to_board' do
    let(:target_board) { create(:kanban_board, account: account) }
    let(:target_step) { create(:kanban_board_step, board: target_board) }

    before do
      create(:kanban_board_inbox, board: target_board, inbox: inbox)
      target_board.update!(steps_order: [target_step.id])
      automation_rule.update!(actions: [{ action_name: 'assign_to_board', action_params: [target_board.id] }])
      task # ensure task is created before the test
    end

    it 'creates a new task on the target board with conversations' do
      expect { service.perform }.to change(FazerAi::Kanban::Task, :count).by(1)

      new_task = FazerAi::Kanban::Task.last
      expect(new_task.board).to eq(target_board)
      expect(new_task.conversations.reload).to include(conversation)
      expect(task.conversations.reload).to be_empty
    end

    it 'adds copied from header to the description' do
      task.update!(description: 'Original description')
      service.perform
      new_task = FazerAi::Kanban::Task.last
      expect(new_task.description).to include(task.board.name)
      expect(new_task.description).to include('Original description')
    end

    context 'when target board is the same as current board' do
      before do
        automation_rule.update!(actions: [{ action_name: 'assign_to_board', action_params: [board.id] }])
      end

      it 'does not create a new task' do
        expect { service.perform }.not_to change(FazerAi::Kanban::Task, :count)
      end
    end

    context 'when conversation inbox is not in target board' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:other_inbox) { create(:inbox, account: account) }
      let(:other_conversation) { create(:conversation, account: account, inbox: other_inbox) }

      before do
        create(:kanban_board_inbox, board: board, inbox: other_inbox)
        task.update!(conversation_ids: [other_conversation.display_id])
      end

      it 'creates task without the invalid conversation and keeps it on old task' do
        service.perform
        new_task = FazerAi::Kanban::Task.last
        expect(new_task.conversations.reload).to be_empty
        expect(task.conversations.reload).to include(other_conversation)
      end
    end

    context 'when action_params is blank' do
      before do
        automation_rule.update!(actions: [{ action_name: 'assign_to_board', action_params: [] }])
      end

      it 'does not create a new task' do
        expect { service.perform }.not_to change(FazerAi::Kanban::Task, :count)
      end
    end
  end
end
