# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::BoardStep, type: :model do
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:board_step) { create(:kanban_board_step, board: board) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(60) }
    it { is_expected.to validate_length_of(:description).is_at_most(120) }
    it { is_expected.to validate_presence_of(:color) }

    describe 'cancelled step validation' do
      let!(:first_step) { create(:kanban_board_step, board: board) }
      let!(:middle_step) { create(:kanban_board_step, board: board) }
      let!(:last_step) { create(:kanban_board_step, board: board) }

      before do
        board.update!(steps_order: [first_step.id, middle_step.id, last_step.id])
      end

      it 'does not allow cancelled on the first step' do
        first_step.cancelled = true
        expect(first_step).not_to be_valid
        expect(first_step.errors[:cancelled]).to include('cannot be set on the first step')
      end

      it 'does not allow cancelled on the last step' do
        last_step.cancelled = true
        expect(last_step).not_to be_valid
        expect(last_step.errors[:cancelled]).to include('cannot be set on the last step')
      end

      it 'allows cancelled on a middle step' do
        middle_step.cancelled = true
        expect(middle_step).to be_valid
      end

      it 'uncancels other steps when setting a step as cancelled' do
        another_middle_step = create(:kanban_board_step, board: board)
        board.update!(steps_order: [first_step.id, middle_step.id, another_middle_step.id, last_step.id])

        middle_step.update!(cancelled: true)
        expect(middle_step.reload.cancelled).to be true

        another_middle_step.update!(cancelled: true)
        expect(another_middle_step.reload.cancelled).to be true
        expect(middle_step.reload.cancelled).to be false
      end
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:board).touch(true) }
    it { is_expected.to have_many(:tasks).dependent(:destroy) }
  end

  describe 'scopes' do
    describe '.ordered' do
      it 'returns steps ordered by created_at asc' do
        step1 = create(:kanban_board_step, board: board, created_at: 2.days.ago)
        step2 = create(:kanban_board_step, board: board, created_at: 1.day.ago)
        step3 = create(:kanban_board_step, board: board, created_at: 3.days.ago)

        expect(described_class.ordered).to eq([step3, step1, step2])
      end
    end
  end

  describe '#inferred_task_status' do
    context 'when board has only one step' do
      let!(:single_step) { create(:kanban_board_step, board: board) }

      before { board.update!(steps_order: [single_step.id]) }

      it 'returns open regardless of position' do
        expect(single_step.inferred_task_status).to eq('open')
      end
    end

    context 'when board has multiple steps' do
      let!(:first_step) { create(:kanban_board_step, board: board) }
      let!(:middle_step) { create(:kanban_board_step, board: board) }
      let!(:last_step) { create(:kanban_board_step, board: board) }

      before do
        board.update!(steps_order: [first_step.id, middle_step.id, last_step.id])
      end

      it 'returns open for the first step' do
        expect(first_step.inferred_task_status).to eq('open')
      end

      it 'returns open for a middle step' do
        expect(middle_step.inferred_task_status).to eq('open')
      end

      it 'returns completed for the last step' do
        expect(last_step.inferred_task_status).to eq('completed')
      end

      it 'returns cancelled for a cancelled step' do
        middle_step.update!(cancelled: true)
        expect(middle_step.inferred_task_status).to eq('cancelled')
      end
    end
  end

  describe '#first_step?' do
    let!(:first_step) { create(:kanban_board_step, board: board) }
    let!(:second_step) { create(:kanban_board_step, board: board) }

    before { board.update!(steps_order: [first_step.id, second_step.id]) }

    it 'returns true for the first step' do
      expect(first_step.first_step?).to be true
    end

    it 'returns false for other steps' do
      expect(second_step.first_step?).to be false
    end
  end

  describe '#last_step?' do
    let!(:first_step) { create(:kanban_board_step, board: board) }
    let!(:second_step) { create(:kanban_board_step, board: board) }

    before { board.update!(steps_order: [first_step.id, second_step.id]) }

    it 'returns true for the last step' do
      expect(second_step.last_step?).to be true
    end

    it 'returns false for other steps' do
      expect(first_step.last_step?).to be false
    end
  end

  describe 'event dispatching' do
    it 'dispatches kanban.step.created event on create' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
        Events::Types::KANBAN_STEP_CREATED,
        an_instance_of(ActiveSupport::TimeWithZone),
        step: an_instance_of(described_class)
      )

      create(:kanban_board_step, board: board)
    end

    it 'dispatches kanban.step.updated event on update' do
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
        Events::Types::KANBAN_STEP_UPDATED,
        an_instance_of(ActiveSupport::TimeWithZone),
        step: board_step
      )

      board_step.update!(name: 'New Name')
    end
  end

  describe '#push_event_data' do
    let!(:first_step) { create(:kanban_board_step, board: board) }
    let!(:step) do
      create(:kanban_board_step,
             board: board,
             name: 'Test Step',
             description: 'Test Description',
             color: '#ff0000',
             cancelled: true)
    end

    before { board.update!(steps_order: [first_step.id, step.id]) }

    it 'returns a hash with all step attributes' do
      data = step.push_event_data

      expect(data).to include(
        id: step.id,
        board_id: board.id,
        name: 'Test Step',
        description: 'Test Description',
        color: '#ff0000',
        tasks_count: step.tasks_count,
        cancelled: true,
        inferred_task_status: 'cancelled'
      )

      expect(data[:created_at]).to be_a(ActiveSupport::TimeWithZone)
      expect(data[:updated_at]).to be_a(ActiveSupport::TimeWithZone)
    end
  end
end
