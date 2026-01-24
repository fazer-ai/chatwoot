# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::Board, type: :model do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(60) }
    it { is_expected.to validate_length_of(:description).is_at_most(2000) }
    it { is_expected.to validate_presence_of(:account) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:steps).dependent(:destroy) }
    it { is_expected.to have_many(:tasks).dependent(:destroy) }
    it { is_expected.to have_many(:board_agents).dependent(:destroy) }
    it { is_expected.to have_many(:assigned_agents).through(:board_agents) }
    it { is_expected.to have_many(:board_inboxes).dependent(:destroy) }
    it { is_expected.to have_many(:inboxes).through(:board_inboxes) }
  end

  describe 'scopes' do
    describe '.ordered' do
      it 'returns boards ordered by created_at asc' do
        board1 = create(:kanban_board, account: account, created_at: 2.days.ago)
        board2 = create(:kanban_board, account: account, created_at: 1.day.ago)
        board3 = create(:kanban_board, account: account, created_at: 3.days.ago)

        expect(described_class.ordered).to eq([board3, board1, board2])
      end
    end
  end

  describe '#includes_inbox?' do
    let(:inbox) { create(:inbox, account: account) }

    it 'returns true if the inbox is associated with the board' do
      create(:kanban_board_inbox, board: board, inbox: inbox)
      expect(board.includes_inbox?(inbox.id)).to be(true)
    end

    it 'returns false if the inbox is not associated with the board' do
      expect(board.includes_inbox?(inbox.id)).to be(false)
    end
  end

  describe 'event dispatching' do
    it 'dispatches kanban.board.updated event when steps_order changes' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
        Events::Types::KANBAN_BOARD_UPDATED,
        an_instance_of(ActiveSupport::TimeWithZone),
        board: board
      )

      board.update!(steps_order: [1, 2, 3])
    end

    it 'dispatches KANBAN_BOARD_UPDATED event when other attributes change' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
        Events::Types::KANBAN_BOARD_UPDATED,
        an_instance_of(ActiveSupport::TimeWithZone),
        board: board
      )

      board.update!(name: 'New Board Name')
    end
  end

  describe '#push_event_data' do
    let(:test_board) do
      create(:kanban_board,
             account: account,
             name: 'Test Board',
             description: 'Test Description',
             steps_order: [1, 2, 3])
    end

    it 'returns a hash with all board attributes' do
      data = test_board.push_event_data

      expect(data).to include(
        id: test_board.id,
        account_id: account.id,
        name: 'Test Board',
        description: 'Test Description',
        settings: test_board.settings,
        steps_order: [1, 2, 3]
      )

      expect(data[:created_at]).to be_a(ActiveSupport::TimeWithZone)
      expect(data[:updated_at]).to be_a(ActiveSupport::TimeWithZone)
    end
  end

  describe '#sync_task_and_conversation_agents?' do
    it 'returns true when setting is enabled' do
      board.settings = { 'sync_task_and_conversation_agents' => true }
      expect(board.sync_task_and_conversation_agents?).to be(true)
    end

    it 'returns false when setting is disabled' do
      board.settings = { 'sync_task_and_conversation_agents' => false }
      expect(board.sync_task_and_conversation_agents?).to be(false)
    end

    it 'returns false when setting is not present' do
      board.settings = {}
      expect(board.sync_task_and_conversation_agents?).to be(false)
    end
  end

  describe '#auto_assign_task_to_agent?' do
    it 'returns true when setting is enabled' do
      board.settings = { 'auto_assign_task_to_agent' => true }
      expect(board.auto_assign_task_to_agent?).to be(true)
    end

    it 'returns false when setting is disabled' do
      board.settings = { 'auto_assign_task_to_agent' => false }
      expect(board.auto_assign_task_to_agent?).to be(false)
    end

    it 'returns false when setting is not present' do
      board.settings = {}
      expect(board.auto_assign_task_to_agent?).to be(false)
    end
  end

  describe '#auto_create_task_for_conversation?' do
    it 'returns true when setting is enabled' do
      board.settings = { 'auto_create_task_for_conversation' => true }
      expect(board.auto_create_task_for_conversation?).to be(true)
    end

    it 'returns false when setting is disabled' do
      board.settings = { 'auto_create_task_for_conversation' => false }
      expect(board.auto_create_task_for_conversation?).to be(false)
    end

    it 'returns false when setting is not present' do
      board.settings = {}
      expect(board.auto_create_task_for_conversation?).to be(false)
    end
  end

  describe '#auto_resolve_conversation_on_task_end?' do
    it 'returns true when setting is enabled' do
      board.settings = { 'auto_resolve_conversation_on_task_end' => true }
      expect(board.auto_resolve_conversation_on_task_end?).to be(true)
    end

    it 'returns false when setting is disabled' do
      board.settings = { 'auto_resolve_conversation_on_task_end' => false }
      expect(board.auto_resolve_conversation_on_task_end?).to be(false)
    end

    it 'returns false when setting is not present' do
      board.settings = {}
      expect(board.auto_resolve_conversation_on_task_end?).to be(false)
    end
  end

  describe '#first_step' do
    let!(:step1) { create(:kanban_board_step, board: board) }
    let!(:step2) { create(:kanban_board_step, board: board) }

    it 'returns the first step in ordered steps' do
      expect(board.first_step).to eq(step1)
    end

    it 'respects steps_order when set' do
      board.update!(steps_order: [step2.id, step1.id])
      expect(board.first_step).to eq(step2)
    end

    it 'returns nil when board has no steps' do
      board.steps.destroy_all
      board.update!(steps_order: [])
      expect(board.first_step).to be_nil
    end
  end

  describe '#auto_complete_task_on_conversation_resolve?' do
    it 'returns true when setting is enabled' do
      board.settings = { 'auto_complete_task_on_conversation_resolve' => true }
      expect(board.auto_complete_task_on_conversation_resolve?).to be(true)
    end

    it 'returns false when setting is disabled' do
      board.settings = { 'auto_complete_task_on_conversation_resolve' => false }
      expect(board.auto_complete_task_on_conversation_resolve?).to be(false)
    end

    it 'returns false when setting is not present' do
      board.settings = {}
      expect(board.auto_complete_task_on_conversation_resolve?).to be(false)
    end
  end

  describe '#completed_step' do
    let!(:step1) { create(:kanban_board_step, board: board) }
    let!(:step2) { create(:kanban_board_step, board: board) }

    it 'returns the last step in ordered steps' do
      expect(board.completed_step).to eq(step2)
    end

    it 'respects steps_order when set' do
      board.update!(steps_order: [step2.id, step1.id])
      expect(board.completed_step).to eq(step1)
    end

    it 'returns nil when board has no steps' do
      board.steps.destroy_all
      board.update!(steps_order: [])
      expect(board.completed_step).to be_nil
    end
  end

  describe '#reset_cancelled_on_first_or_last_step' do
    let!(:first_step) { create(:kanban_board_step, board: board) }
    let!(:middle_step) { create(:kanban_board_step, board: board) }
    let!(:last_step) { create(:kanban_board_step, board: board) }

    before do
      board.update!(steps_order: [first_step.id, middle_step.id, last_step.id])
      middle_step.update!(cancelled: true)
    end

    it 'clears cancelled flag when a cancelled step is moved to first position' do
      board.update!(steps_order: [middle_step.id, first_step.id, last_step.id])

      expect(middle_step.reload.cancelled).to be(false)
    end

    it 'clears cancelled flag when a cancelled step is moved to last position' do
      board.update!(steps_order: [first_step.id, last_step.id, middle_step.id])

      expect(middle_step.reload.cancelled).to be(false)
    end

    it 'keeps cancelled flag when step remains in the middle' do
      board.update!(steps_order: [last_step.id, middle_step.id, first_step.id])

      expect(middle_step.reload.cancelled).to be(true)
    end

    it 'does nothing when steps_order is blank' do
      board.update!(steps_order: [])

      expect(middle_step.reload.cancelled).to be(true)
    end
  end

  describe 'deletion' do
    context 'when board has tasks' do
      it 'successfully deletes board and all associated records' do
        step = create(:kanban_board_step, board: board)
        create(:kanban_task, board: board, board_step: step)

        expect { board.destroy! }.to(
          change(described_class, :count).by(-1)
          .and(change(FazerAi::Kanban::BoardStep, :count).by(-1)
          .and(change(FazerAi::Kanban::Task, :count).by(-1)))
        )
      end

      it 'handles task callbacks gracefully when step is already deleted' do
        step = create(:kanban_board_step, board: board)
        task = create(:kanban_task, board: board, board_step: step)

        # Verify task's after_destroy callback doesn't fail when step is deleted first
        expect { board.destroy! }.not_to raise_error
        expect(FazerAi::Kanban::Task.exists?(task.id)).to be(false)
      end
    end
  end
end
