# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::Boards' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:base_path) { "/api/v1/accounts/#{account.id}/kanban/boards" }

  before { account.enable_features('kanban') }

  describe 'GET /api/v1/accounts/:account_id/kanban/boards' do
    it 'returns boards scoped to the account' do
      create_list(:kanban_board, 2, account: account)

      get base_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['boards'].size).to eq(2)
    end

    it 'returns 404 when the feature flag is disabled' do
      account.disable_features('kanban')

      get base_path, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    context 'with sorting and preferences' do
      let!(:board_a) { create(:kanban_board, account: account, name: 'Alpha', updated_at: 2.days.ago) } # rubocop:disable RSpec/LetSetup
      let!(:board_b) { create(:kanban_board, account: account, name: 'Beta', updated_at: 1.day.ago) } # rubocop:disable RSpec/LetSetup
      let(:account_user) { AccountUser.find_by(user: admin, account: account) }
      let(:default_preferences) do
        {
          'board_sorting' => { 'sort' => 'updated_at', 'order' => 'desc' }
        }
      end

      before do
        stub_const('FazerAi::Kanban::AccountUserPreference::DEFAULT_PREFERENCES', default_preferences)
        FazerAi::Kanban::AccountUserPreference.where(account_user: account_user).delete_all
      end

      it 'sorts boards by specified column and direction' do
        get base_path, params: { sort: 'name', order: 'desc' }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['boards'].map { |f| f['name'] }).to eq(%w[Beta Alpha])
      end

      it 'persists sort preferences and returns them in response' do
        expect do
          get base_path, params: { sort: 'name', order: 'desc' }, headers: headers
        end.to change(FazerAi::Kanban::AccountUserPreference, :count).by(1)

        expect(response.parsed_body['preferences']['board_sorting']).to eq({ 'sort' => 'name', 'order' => 'desc' })
      end

      it 'applies saved preferences when no sort params provided' do
        create(:kanban_account_user_preference, account_user: account_user, preferences: {
                 'board_sorting' => { 'sort' => 'updated_at', 'order' => 'desc' }
               })

        get base_path, headers: headers

        expect(response.parsed_body['boards'].map { |f| f['name'] }).to eq(%w[Beta Alpha])
      end

      it 'falls back to defaults for invalid sort params' do
        get base_path, params: { sort: 'invalid', order: 'invalid' }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['preferences']['board_sorting']).to eq(default_preferences['board_sorting'])
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/kanban/boards/:id' do
    let!(:board) { create(:kanban_board, account: account, name: 'Enterprise Leads') }
    let!(:inbox) { create(:inbox, account: account, name: 'Inbox Demo') }
    let!(:board_inbox) { create(:kanban_board_inbox, board: board, inbox: inbox) } # rubocop:disable RSpec/LetSetup
    let!(:agent) { create(:user, account: account, name: 'Board Owner') }
    let!(:board_agent) { create(:kanban_board_agent, board: board, agent: agent) } # rubocop:disable RSpec/LetSetup

    it 'returns the board details' do
      get "#{base_path}/#{board.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['name']).to eq('Enterprise Leads')
      expect(response.parsed_body['assigned_inbox_ids']).to include(inbox.id)
      serialized_inbox = response.parsed_body['assigned_inboxes'].find { |row| row['id'] == inbox.id }
      expect(serialized_inbox).to include('name' => 'Inbox Demo', 'channel_type' => inbox.channel_type)
      expect(response.parsed_body['assigned_agent_ids']).to include(agent.id)
      serialized_agent = response.parsed_body['assigned_agents'].find { |row| row['id'] == agent.id }
      expect(serialized_agent).to include('name' => 'Board Owner', 'email' => agent.email)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/kanban/boards' do
    let(:params) do
      {
        board: {
          name: 'Sales Board',
          description: 'Top of board work',
          settings: { auto_assign: false }
        }
      }
    end

    it 'creates a board and returns it' do
      expect do
        post base_path, params: params, headers: headers
      end.to change { account.kanban_boards.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['name']).to eq('Sales Board')
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/kanban/boards/:id' do
    let!(:board) { create(:kanban_board, account: account, name: 'North America') }

    let(:params) do
      {
        board: {
          name: 'Global Board',
          settings: { auto_assign: true }
        }
      }
    end

    it 'updates the board attributes' do
      patch "#{base_path}/#{board.id}", params: params, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      board.reload
      expect(board.name).to eq('Global Board')
      expect(board.settings).to include('auto_assign' => true)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/kanban/boards/:id/toggle_favorite' do
    let!(:board) { create(:kanban_board, account: account) }

    it 'adds the board to favorites if not present' do
      post "#{base_path}/#{board.id}/toggle_favorite", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['favorite_board_ids']).to include(board.id)

      preference = FazerAi::Kanban::AccountUserPreference.find_by(account_user: admin.account_users.find_by(account: account))
      expect(preference.preferences['favorite_board_ids']).to include(board.id)
    end

    it 'removes the board from favorites if present' do
      account_user = admin.account_users.find_by(account: account)
      create(:kanban_account_user_preference, account_user: account_user, preferences: { 'favorite_board_ids' => [board.id] })

      post "#{base_path}/#{board.id}/toggle_favorite", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['favorite_board_ids']).not_to include(board.id)

      preference = account_user.kanban_preference.reload
      expect(preference.preferences['favorite_board_ids']).not_to include(board.id)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/kanban/boards/:id' do
    let!(:board) { create(:kanban_board, account: account) }

    it 'destroys the board and returns no content' do
      expect do
        delete "#{base_path}/#{board.id}", headers: headers
      end.to change { account.kanban_boards.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
