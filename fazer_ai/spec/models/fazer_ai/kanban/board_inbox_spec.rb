# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::BoardInbox, type: :model do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:other_account) { create(:account) }
  let(:foreign_inbox) { create(:inbox, account: other_account) }

  describe 'validations' do
    subject { create(:kanban_board_inbox, board: board, inbox: create(:inbox, account: account)) }

    it { is_expected.to validate_uniqueness_of(:inbox_id).scoped_to(:board_id) }

    it 'rejects inboxes that belong to a different account' do
      link = build(:kanban_board_inbox, board: board, inbox: foreign_inbox)

      expect(link).not_to be_valid
      expect(link.errors[:inbox_id]).to include(I18n.t('kanban.inboxes.errors.mismatched_account'))
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:board) }
    it { is_expected.to belong_to(:inbox) }
  end

  describe 'callbacks' do
    describe '#cleanup_task_conversations' do
      let(:inbox) { create(:inbox, account: account) }
      let(:board_inbox) { create(:kanban_board_inbox, board: board, inbox: inbox) }
      let(:task) { create(:kanban_task, board: board) }
      let(:conversation) { create(:conversation, inbox: inbox, account: account) }

      it 'removes task assignment from conversations when board_inbox is destroyed' do
        conversation.update!(kanban_task: task)

        expect { board_inbox.destroy }.to change { conversation.reload.kanban_task_id }.from(task.id).to(nil)
      end

      it 'does not remove task assignment from conversations in other inboxes' do
        other_inbox = create(:inbox, account: account)
        other_conversation = create(:conversation, inbox: other_inbox, account: account, kanban_task: task)

        expect { board_inbox.destroy }.not_to(change { other_conversation.reload.kanban_task_id })
      end

      it 'does not remove task assignment from conversations in other boards' do
        other_board = create(:kanban_board, account: account)
        other_task = create(:kanban_task, board: other_board)
        conversation.update!(kanban_task: other_task)

        expect { board_inbox.destroy }.not_to(change { conversation.reload.kanban_task_id })
      end

      it 'removes task assignment from multiple conversations in the same inbox' do
        task2 = create(:kanban_task, board: board)
        conversation2 = create(:conversation, inbox: inbox, account: account)

        conversation.update!(kanban_task: task)
        conversation2.update!(kanban_task: task2)

        expect { board_inbox.destroy }.to(
          change { [conversation.reload.kanban_task_id, conversation2.reload.kanban_task_id] }
            .from([task.id, task2.id])
            .to([nil, nil])
        )
      end
    end
  end
end
