# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::ActionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:board_inbox) { create(:kanban_board_inbox, board: board, inbox: inbox) } # rubocop:disable RSpec/LetSetup
  let!(:step) { create(:kanban_board_step, board: board) }
  let(:task) { create(:kanban_task, account: account, board: board, board_step: step, conversation_ids: [conversation.display_id]) }
  let(:action_service) { ActionService.new(conversation) }

  describe '#add_label_to_task' do
    context 'when conversation has a task' do
      before { task }

      it 'adds labels to the task' do
        action_service.add_label_to_task(%w[priority bug])
        expect(task.reload.label_list).to contain_exactly('priority', 'bug')
      end

      it 'adds new labels while keeping existing ones' do
        task.update!(label_list: ['existing'])
        action_service.add_label_to_task(%w[priority bug])
        expect(task.reload.label_list).to contain_exactly('existing', 'priority', 'bug')
      end
    end

    context 'when conversation does not have a task' do
      it 'does nothing' do
        expect { action_service.add_label_to_task(%w[priority bug]) }.not_to raise_error
      end
    end

    context 'when labels are blank' do
      before { task }

      it 'does not change labels' do
        action_service.add_label_to_task([])
        expect(task.reload.label_list).to be_empty
      end
    end
  end

  describe '#remove_label_from_task' do
    context 'when conversation has a task' do
      before do
        task.update!(label_list: %w[priority bug feature])
      end

      it 'removes specified labels from the task' do
        action_service.remove_label_from_task(%w[priority bug])
        expect(task.reload.label_list).to contain_exactly('feature')
      end

      it 'does not affect labels that do not exist' do
        action_service.remove_label_from_task(['nonexistent'])
        expect(task.reload.label_list).to contain_exactly('priority', 'bug', 'feature')
      end
    end

    context 'when conversation does not have a task' do
      it 'does nothing' do
        expect { action_service.remove_label_from_task(%w[priority bug]) }.not_to raise_error
      end
    end

    context 'when labels are blank' do
      before do
        task.update!(label_list: ['existing'])
      end

      it 'does not change labels' do
        action_service.remove_label_from_task([])
        expect(task.reload.label_list).to contain_exactly('existing')
      end
    end
  end
end
