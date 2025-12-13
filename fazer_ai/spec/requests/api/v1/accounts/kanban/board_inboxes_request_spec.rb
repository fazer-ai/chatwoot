# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::BoardInboxes' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:board) { create(:kanban_board, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/kanban/boards/#{board.id}/inboxes" }
  let(:json_headers) { headers.merge('Content-Type' => 'application/json') }

  before { account.enable_features('kanban') }

  describe 'GET /api/v1/accounts/:account_id/kanban/boards/:board_id/inboxes' do
    it 'returns inbox links for the board' do
      create(:kanban_board_inbox, board: board, inbox: inbox)

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['board_inboxes']
      expect(payload.size).to eq(1)
      expect(payload.first['inbox_id']).to eq(inbox.id)
      expect(payload.first.dig('inbox', 'name')).to eq(inbox.name)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/kanban/boards/:board_id/inboxes' do
    let(:params) do
      {
        board_inbox: {
          inbox_id: inbox.id
        }
      }
    end

    it 'creates a board inbox link' do
      expect do
        post base_path, params: params.to_json, headers: json_headers
      end.to change { board.reload.board_inboxes.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['inbox_id']).to eq(inbox.id)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/kanban/boards/:board_id/inboxes/:id' do
    let!(:board_inbox) { create(:kanban_board_inbox, board: board, inbox: inbox) }

    it 'removes the board inbox link' do
      expect do
        delete "#{base_path}/#{board_inbox.id}", headers: headers
      end.to change { board.reload.board_inboxes.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
