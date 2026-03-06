# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::TriggerTaskDueWebhookJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:first_step) { create(:kanban_board_step, board: board) }
  let!(:middle_step) { create(:kanban_board_step, board: board) }
  let!(:last_step) { create(:kanban_board_step, board: board) }

  before do
    board.update!(steps_order: [first_step.id, middle_step.id, last_step.id])
  end

  describe '#perform' do
    context 'when task is open and overdue' do
      it 'enqueues webhook job with task data' do
        task = create(:kanban_task, board: board, board_step: middle_step, due_date: 2.minutes.ago)
        webhook = create(:webhook, account: account, subscriptions: ['kanban_task_overdue'])

        expect do
          job.perform(task)
        end.to have_enqueued_job(WebhookJob).with(webhook.url, hash_including(event: 'kanban_task_overdue', id: task.id))
      end

      it 'includes the task push event data in the payload' do
        task = create(:kanban_task, board: board, board_step: middle_step, due_date: 2.minutes.ago)
        webhook = create(:webhook, account: account, subscriptions: ['kanban_task_overdue'])

        expect(WebhookJob).to receive(:perform_later) do |url, payload|
          expect(url).to eq(webhook.url)
          expect(payload[:event]).to eq('kanban_task_overdue')
          expect(payload[:id]).to eq(task.id)
          expect(payload[:title]).to eq(task.title)
          expect(payload[:due_date]).to eq(task.due_date)
        end

        job.perform(task)
      end
    end

    context 'when task is in completed step (last step)' do
      it 'does not enqueue webhook job' do
        task = create(:kanban_task, board: board, board_step: last_step, due_date: 2.minutes.ago)
        create(:webhook, account: account, subscriptions: ['kanban_task_overdue'])

        expect do
          job.perform(task)
        end.not_to have_enqueued_job(WebhookJob)
      end
    end

    context 'when task due_date was changed to the future after enqueue' do
      it 'does not enqueue webhook job' do
        task = create(:kanban_task, board: board, board_step: middle_step, due_date: 1.hour.from_now)
        create(:webhook, account: account, subscriptions: ['kanban_task_overdue'])

        expect do
          job.perform(task)
        end.not_to have_enqueued_job(WebhookJob)
      end
    end

    context 'when webhook is not subscribed to kanban_task_overdue' do
      it 'does not enqueue webhook job' do
        task = create(:kanban_task, board: board, board_step: middle_step, due_date: 2.minutes.ago)
        create(:webhook, account: account, subscriptions: ['kanban_task_created'])

        expect do
          job.perform(task)
        end.not_to have_enqueued_job(WebhookJob)
      end
    end

    context 'with multiple webhooks subscribed' do
      it 'enqueues webhook job for each subscribed webhook' do
        task = create(:kanban_task, board: board, board_step: middle_step, due_date: 2.minutes.ago)
        webhook1 = create(:webhook, account: account, url: 'https://example.com/webhook1', subscriptions: ['kanban_task_overdue'])
        webhook2 = create(:webhook, account: account, url: 'https://example.com/webhook2', subscriptions: ['kanban_task_overdue'])
        create(:webhook, account: account, url: 'https://example.com/webhook3', subscriptions: ['kanban_task_created']) # not subscribed

        expect do
          job.perform(task)
        end.to have_enqueued_job(WebhookJob).with(webhook1.url, hash_including(id: task.id))
           .and have_enqueued_job(WebhookJob).with(webhook2.url, hash_including(id: task.id))
      end
    end
  end
end
