# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::BoardSteps' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:board) { create(:kanban_board, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/kanban/boards/#{board.id}/steps" }

  before { account.enable_features('kanban_module') }

  describe 'GET /api/v1/accounts/:account_id/kanban/boards/:board_id/steps' do
    it 'returns ordered steps for the board' do
      create(:kanban_board_step, board: board, name: 'Prospecting')
      create(:kanban_board_step, board: board, name: 'Qualified')

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      names = response.parsed_body['steps'].map { |step| step['name'] }
      expect(names).to include('Prospecting', 'Qualified')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/kanban/boards/:board_id/steps/:id' do
    let!(:step) { create(:kanban_board_step, board: board, name: 'Demo Scheduled') }

    it 'returns the step attributes' do
      get "#{base_path}/#{step.id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['name']).to eq('Demo Scheduled')
      expect(body['board_id']).to eq(board.id)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/kanban/boards/:board_id/steps' do
    let(:params) do
      {
        step: {
          name: 'Negotiation',
          description: 'Final pricing discussions',
          color: '#10b981'
        }
      }
    end

    it 'creates the step and returns it' do
      expect do
        post base_path, params: params, headers: headers
      end.to change { board.steps.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['name']).to eq('Negotiation')
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/kanban/boards/:board_id/steps/:id' do
    let!(:step) { create(:kanban_board_step, board: board, name: 'Initial Review') }

    let(:params) do
      {
        step: {
          name: 'Final Review'
        }
      }
    end

    it 'updates the board step' do
      patch "#{base_path}/#{step.id}", params: params, headers: headers

      expect(response).to have_http_status(:ok)
      expect(step.reload).to have_attributes(name: 'Final Review')
    end

    context 'when updating cancelled attribute' do
      let!(:first_step) { create(:kanban_board_step, board: board) }
      let!(:middle_step) { create(:kanban_board_step, board: board) }
      let!(:last_step) { create(:kanban_board_step, board: board) }

      before do
        board.update!(steps_order: [first_step.id, middle_step.id, last_step.id])
      end

      it 'allows setting cancelled on a middle step' do
        patch "#{base_path}/#{middle_step.id}", params: { step: { cancelled: true } }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(middle_step.reload.cancelled).to be true
        expect(response.parsed_body['inferred_task_status']).to eq('cancelled')
      end

      it 'rejects setting cancelled on the first step' do
        patch "#{base_path}/#{first_step.id}", params: { step: { cancelled: true } }, headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(first_step.reload.cancelled).to be false
      end

      it 'rejects setting cancelled on the last step' do
        patch "#{base_path}/#{last_step.id}", params: { step: { cancelled: true } }, headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(last_step.reload.cancelled).to be false
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/kanban/boards/:board_id/steps/:id' do
    let!(:step_1) { create(:kanban_board_step, board: board) }
    let!(:step_2) { create(:kanban_board_step, board: board) }
    let!(:step_3) { create(:kanban_board_step, board: board) }

    before do
      board.update!(steps_order: [step_1.id, step_2.id, step_3.id])
    end

    it 'removes the board step' do
      expect do
        delete "#{base_path}/#{step_2.id}", headers: headers
      end.to change { board.steps.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end

    context 'when step has tasks' do
      context 'when deleting a middle step' do
        let!(:task) { create(:kanban_task, board: board, board_step: step_2, account: account, creator: admin) }

        it 'moves tasks to the previous step' do
          delete "#{base_path}/#{step_2.id}", headers: headers

          expect(response).to have_http_status(:no_content)
          expect(task.reload.board_step_id).to eq(step_1.id)
        end
      end

      context 'when deleting the first step' do
        let!(:task) { create(:kanban_task, board: board, board_step: step_1, account: account, creator: admin) }

        it 'moves tasks to the next step' do
          delete "#{base_path}/#{step_1.id}", headers: headers

          expect(response).to have_http_status(:no_content)
          expect(task.reload.board_step_id).to eq(step_2.id)
        end
      end
    end
  end
end
