# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TriggerScheduledItemsJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:first_step) { create(:kanban_board_step, board: board) }
  let!(:middle_step) { create(:kanban_board_step, board: board) }
  let!(:last_step) { create(:kanban_board_step, board: board) }

  before do
    board.update!(steps_order: [first_step.id, middle_step.id, last_step.id])
  end

  describe 'kanban task due webhooks' do
    it 'enqueues TriggerTaskDueWebhookJob for due tasks' do
      task = create(:kanban_task, board: board, board_step: middle_step, due_date: 2.minutes.ago)

      expect do
        job.perform
      end.to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob).with(task)
    end

    it 'does not enqueue job for tasks outside the scheduling window' do
      create(:kanban_task, board: board, board_step: middle_step, due_date: 1.hour.from_now)

      expect do
        job.perform
      end.not_to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob)
    end

    it 'filters out tasks in cancelled steps at DB level' do
      cancelled_step = create(:kanban_board_step, board: board)
      board.update!(steps_order: [first_step.id, middle_step.id, cancelled_step.id, last_step.id])
      cancelled_step.update!(cancelled: true)

      create(:kanban_task, board: board, board_step: cancelled_step, due_date: 2.minutes.ago)

      expect do
        job.perform
      end.not_to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob)
    end
  end
end
