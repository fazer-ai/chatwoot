# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::Tasks' do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:board) { create(:kanban_board, account: account) }
  let(:board_step) { create(:kanban_board_step, board: board) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/kanban/tasks" }

  before { account.enable_features('kanban_module') }

  def admin_preference
    admin.account_users.find_by(account_id: account.id).kanban_preference
  end

  describe 'GET /api/v1/accounts/:account_id/kanban/tasks' do
    it 'returns tasks filtered by account' do
      create(:kanban_task, account: account, board: board, board_step: board_step)

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['tasks'].size).to eq(1)
    end

    context 'with sorting' do
      it 'updates preferences when sorting by position' do
        get base_path, params: { sort: 'position', order: 'asc', board_id: board.id }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(admin_preference.preferences['task_sorting'][board.id.to_s]).to eq({ 'sort' => 'position', 'order' => 'asc' })
      end

      it 'updates preferences when sorting by priority' do
        get base_path, params: { sort: 'priority', order: 'desc', board_id: board.id }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(admin_preference.preferences['task_sorting'][board.id.to_s]).to eq({ 'sort' => 'priority', 'order' => 'desc' })
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/kanban/tasks/:id' do
    let!(:task) do
      create(:kanban_task, account: account, board: board, board_step: board_step, title: 'Initial Outreach')
    end

    it 'returns the task payload' do
      get "#{base_path}/#{task.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['title']).to eq('Initial Outreach')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/kanban/tasks' do
    let(:params) do
      {
        task: {
          title: 'Follow up',
          description: 'Check in with the lead',
          priority: 'normal',
          board_id: board.id,
          board_step_id: board_step.id
        }
      }
    end

    it 'creates a task and enqueues an audit job' do
      expect do
        post base_path, params: params, headers: headers
      end.to change { account.kanban_tasks.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['title']).to eq('Follow up')
      expect(FazerAi::Kanban::AuditEventJob).to have_been_enqueued
    end

    context 'when attaching conversations respecting board inboxes' do
      let(:inbox) { create(:inbox, account: account) }
      let(:other_inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before { create(:kanban_board_inbox, board: board, inbox: inbox) }

      it 'persists when conversation inbox matches board inbox' do
        post base_path, params: { task: params[:task].merge(conversation_ids: [conversation.id]) }, headers: headers

        expect(response).to have_http_status(:created)
        task_id = response.parsed_body['id']
        task = FazerAi::Kanban::Task.find(task_id)
        expect(task.conversation_ids).to contain_exactly(conversation.id)
      end

      it 'rejects conversations from another inbox linked to the account' do
        mismatched_conversation = create(:conversation, account: account, inbox: other_inbox)

        expect do
          post base_path, params: { task: params[:task].merge(conversation_ids: [mismatched_conversation.id]) }, headers: headers
        end.not_to(change { account.kanban_tasks.count })

        expect(response).to have_http_status(:unprocessable_entity)
        error_message = "Conversations #{I18n.t('kanban.tasks.errors.invalid_conversation_inbox')}"
        expect(response.parsed_body['errors']).to include(error_message)
      end
    end

    context 'when insert_before_task_id is provided' do
      let!(:task1) { create(:kanban_task, account: account, board: board, board_step: board_step) }
      let!(:task2) { create(:kanban_task, account: account, board: board, board_step: board_step) }

      before do
        preference = admin.account_users.find_by(account_id: account.id).create_kanban_preference
        preference.update_tasks_order!(board_step.id, [task1.id, task2.id])
      end

      it 'creates a task and positions it before the specified task' do
        post base_path, params: params.merge(insert_before_task_id: task2.id), headers: headers

        expect(response).to have_http_status(:created)
        new_task = FazerAi::Kanban::Task.find(response.parsed_body['id'])

        expect(admin_preference.reload.tasks_order_for(board_step.id)).to eq([task1.id, new_task.id, task2.id])
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/kanban/tasks/:id' do
    let!(:task) do
      create(
        :kanban_task,
        account: account,
        board: board,
        board_step: board_step,
        creator: admin,
        title: 'Initial Title'
      )
    end

    let(:params) do
      {
        task: {
          title: 'Updated Title'
        }
      }
    end

    it 'updates the task and enqueues an audit job with metadata' do
      patch "#{base_path}/#{task.id}", params: params, headers: headers

      expect(response).to have_http_status(:ok)
      expect(task.reload.title).to eq('Updated Title')

      expect(FazerAi::Kanban::AuditEventJob).to have_been_enqueued.with(
        hash_including(
          action: 'task.updated',
          metadata: hash_including(
            changes: hash_including('title' => ['Initial Title', 'Updated Title'])
          )
        )
      )
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/kanban/tasks/:id' do
    let!(:task) do
      create(:kanban_task, account: account, board: board, board_step: board_step, creator: admin)
    end

    it 'destroys the task' do
      expect do
        delete "#{base_path}/#{task.id}", headers: headers
      end.to change { account.kanban_tasks.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/kanban/tasks/:id/move' do
    let!(:task) { create(:kanban_task, account: account, board: board, board_step: board_step) }
    let(:target_step) { create(:kanban_board_step, board: board) }

    context 'when moving to a different step' do
      it 'updates the board_step_id' do
        post "#{base_path}/#{task.id}/move", params: { board_step_id: target_step.id }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(task.reload.board_step_id).to eq(target_step.id)
      end
    end

    context 'when reordering within the same step' do
      let!(:task2) { create(:kanban_task, account: account, board: board, board_step: board_step) }
      let!(:task3) { create(:kanban_task, account: account, board: board, board_step: board_step) }

      before do
        preference = admin.account_users.find_by(account_id: account.id).create_kanban_preference
        preference.update_tasks_order!(board_step.id, [task.id, task2.id, task3.id])
      end

      it 'reorders the task' do
        post "#{base_path}/#{task.id}/move", params: { insert_before_task_id: task3.id }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(admin_preference.reload.tasks_order_for(board_step.id)).to eq([task2.id, task.id, task3.id])
      end
    end

    context 'when moving to a different step with positioning' do
      let!(:target_task1) { create(:kanban_task, account: account, board: board, board_step: target_step) }
      let!(:target_task2) { create(:kanban_task, account: account, board: board, board_step: target_step) }

      before do
        preference = admin.account_users.find_by(account_id: account.id).create_kanban_preference
        preference.update_tasks_order!(target_step.id, [target_task1.id, target_task2.id])
      end

      it 'moves and positions the task' do
        post "#{base_path}/#{task.id}/move", params: { board_step_id: target_step.id, insert_before_task_id: target_task2.id }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(task.reload.board_step_id).to eq(target_step.id)
        expect(admin_preference.reload.tasks_order_for(target_step.id)).to eq([target_task1.id, task.id, target_task2.id])
      end
    end

    context 'when moving to the end of the list' do
      let!(:task2) { create(:kanban_task, account: account, board: board, board_step: board_step) }

      before do
        preference = admin.account_users.find_by(account_id: account.id).create_kanban_preference
        preference.update_tasks_order!(board_step.id, [task.id, task2.id])
      end

      it 'moves the task to the end' do
        post "#{base_path}/#{task.id}/move", params: { insert_before_task_id: nil }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(admin_preference.reload.tasks_order_for(board_step.id)).to eq([task2.id, task.id])
      end
    end
  end
end
