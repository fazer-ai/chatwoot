# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::BoardAgents' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:board) { create(:kanban_board, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/kanban/boards/#{board.id}/agents" }
  let(:json_headers) { headers.merge('Content-Type' => 'application/json') }

  before { account.enable_features('kanban') }

  describe 'GET /api/v1/accounts/:account_id/kanban/boards/:board_id/agents' do
    it 'returns agents scoped to the board' do
      create(:kanban_board_agent, board: board, agent: agent)

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['agents'].size).to eq(1)
      payload = response.parsed_body['agents'].first
      expect(payload['agent_id']).to eq(agent.id)
      expect(payload.dig('agent', 'id')).to eq(agent.id)
      expect(payload.dig('agent', 'name')).to eq(agent.name)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/kanban/boards/:board_id/agents' do
    let(:params) do
      {
        agent: {
          agent_id: agent.id
        }
      }
    end

    it 'creates an agent assignment' do
      expect do
        post base_path, params: params.to_json, headers: json_headers
      end.to change { board.reload.board_agents.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['agent_id']).to eq(agent.id)
      expect(response.parsed_body.dig('agent', 'id')).to eq(agent.id)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/kanban/boards/:board_id/agents/:id' do
    let!(:board_agent) { create(:kanban_board_agent, board: board, agent: agent) }

    it 'removes the agent assignment' do
      expect do
        delete "#{base_path}/#{board_agent.id}", headers: headers
      end.to change { board.reload.board_agents.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
