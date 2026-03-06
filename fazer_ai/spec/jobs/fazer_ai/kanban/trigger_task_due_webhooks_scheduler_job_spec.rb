# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::TriggerTaskDueWebhooksSchedulerJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:first_step) { create(:kanban_board_step, board: board) }
  let!(:middle_step) { create(:kanban_board_step, board: board) }
  let!(:last_step) { create(:kanban_board_step, board: board) }

  before do
    board.update!(steps_order: [first_step.id, middle_step.id, last_step.id])
  end

  it 'enqueues TriggerTaskDueWebhookJob for due tasks' do
    task = create(:kanban_task, board: board, board_step: middle_step, due_date: 30.seconds.ago)

    expect do
      job.perform
    end.to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob).with(task)
  end

  it 'does not enqueue job for tasks not yet due' do
    create(:kanban_task, board: board, board_step: middle_step, due_date: 1.hour.from_now)

    expect do
      job.perform
    end.not_to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob)
  end

  it 'enqueues job for tasks that are already overdue within the catch-up window' do
    task = create(:kanban_task, board: board, board_step: middle_step, due_date: 5.minutes.ago)

    expect do
      job.perform
    end.to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob).with(task)
  end

  it 'does not enqueue job for tasks that became due before the catch-up window' do
    create(:kanban_task, board: board, board_step: middle_step, due_date: 15.minutes.ago)

    expect do
      job.perform
    end.not_to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob)
  end

  it 'filters out tasks in cancelled steps at DB level' do
    cancelled_step = create(:kanban_board_step, board: board)
    board.update!(steps_order: [first_step.id, middle_step.id, cancelled_step.id, last_step.id])
    cancelled_step.update!(cancelled: true)

    create(:kanban_task, board: board, board_step: cancelled_step, due_date: 30.seconds.ago)

    expect do
      job.perform
    end.not_to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob)
  end

  it 'does not enqueue job for tasks already notified' do
    create(:kanban_task, board: board, board_step: middle_step, due_date: 30.seconds.ago, overdue_notified_at: 1.minute.ago)

    expect do
      job.perform
    end.not_to have_enqueued_job(FazerAi::Kanban::TriggerTaskDueWebhookJob)
  end

  it 'sets overdue_notified_at when claiming a task for enqueue' do
    task = create(:kanban_task, board: board, board_step: middle_step, due_date: 30.seconds.ago)

    expect(task.overdue_notified_at).to be_nil

    freeze_time do
      job.perform
      expect(task.reload.overdue_notified_at).to eq(Time.current)
    end
  end

  it 'resets overdue_notified_at if perform_later fails' do
    task = create(:kanban_task, board: board, board_step: middle_step, due_date: 30.seconds.ago)

    allow(FazerAi::Kanban::TriggerTaskDueWebhookJob).to receive(:perform_later).and_raise(Redis::ConnectionError)

    job.perform

    expect(task.reload.overdue_notified_at).to be_nil
  end
end
