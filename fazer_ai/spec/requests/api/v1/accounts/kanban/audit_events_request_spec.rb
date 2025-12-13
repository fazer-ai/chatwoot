# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::AuditEvents' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:board) { create(:kanban_board, account: account) }
  let(:board_step) { create(:kanban_board_step, board: board) }
  let(:task) { create(:kanban_task, account: account, board: board, board_step: board_step, creator: admin) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/kanban/tasks/#{task.id}/audit_events" }

  before { account.enable_features('kanban') }

  describe 'GET /api/v1/accounts/:account_id/kanban/tasks/:task_id/audit_events' do
    it 'returns audit events ordered by recency' do
      older_event = create(:kanban_audit_event, task: task, action: 'task.created', created_at: 1.day.ago)
      recent_event = create(:kanban_audit_event, task: task, action: 'task.updated', created_at: Time.current)

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['audit_events']
      expect(payload.size).to eq(2)
      expect(payload.first['id']).to eq(recent_event.id)
      expect(payload.last['id']).to eq(older_event.id)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/kanban/tasks/:task_id/audit_events/:id' do
    let!(:audit_event) do
      create(:kanban_audit_event, task: task, action: 'task.updated', metadata: { 'field' => 'title' }, actor: admin)
    end

    it 'returns the audit event payload' do
      get "#{base_path}/#{audit_event.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['action']).to eq('task.updated')
      expect(response.parsed_body['metadata']).to eq('field' => 'title')
      expect(response.parsed_body.dig('actor', 'id')).to eq(admin.id)
    end
  end
end
