# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::AccountUserPreferences' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }

  before do
    account.enable_features('kanban')
  end

  describe 'PUT /api/v1/accounts/{account.id}/kanban/account_user_preferences' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/kanban/account_user_preferences"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin' do
      it 'creates a new preference record and updates preferences' do
        put "/api/v1/accounts/#{account.id}/kanban/account_user_preferences",
            params: {
              preferences: {
                board_filters: {
                  '1' => {
                    agent_id: 'all',
                    inbox_id: 'all'
                  }
                }
              }
            },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:no_content)

        admin_account_user = account.account_users.find_by!(user: admin)
        preference = admin_account_user.kanban_preference
        expect(preference).to be_present
        expect(preference.preferences['board_filters']['1']['agent_id']).to eq('all')
        expect(preference.preferences['board_filters']['1']['inbox_id']).to eq('all')
      end

      it 'updates existing preferences with deep merge' do
        admin_account_user = account.account_users.find_by!(user: admin)
        existing_preference = create(
          :kanban_account_user_preference,
          account_user: admin_account_user,
          preferences: {
            board_filters: {
              '1' => {
                agent_id: '123',
                inbox_id: '456'
              },
              '2' => {
                agent_id: '789',
                inbox_id: '012'
              }
            },
            other_setting: 'preserved'
          }
        )

        put "/api/v1/accounts/#{account.id}/kanban/account_user_preferences",
            params: {
              preferences: {
                board_filters: {
                  '1' => {
                    agent_id: 'all'
                  }
                }
              }
            },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:no_content)

        existing_preference.reload
        expect(existing_preference.preferences['board_filters']['1']['agent_id']).to eq('all')
        expect(existing_preference.preferences['board_filters']['1']['inbox_id']).to eq('456')
        expect(existing_preference.preferences['board_filters']['2']['agent_id']).to eq('789')
        expect(existing_preference.preferences['other_setting']).to eq('preserved')
      end
    end

    context 'when it is an authenticated agent' do
      it 'updates their own preferences' do
        put "/api/v1/accounts/#{account.id}/kanban/account_user_preferences",
            params: {
              preferences: {
                board_filters: {
                  '1' => {
                    agent_id: 'all',
                    inbox_id: 'all'
                  }
                }
              }
            },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:no_content)

        agent_account_user = account.account_users.find_by!(user: agent)
        preference = agent_account_user.kanban_preference
        expect(preference).to be_present
        expect(preference.preferences['board_filters']['1']['agent_id']).to eq('all')
      end
    end

    context 'when feature is disabled' do
      before do
        account.disable_features('kanban')
      end

      it 'returns not found' do
        put "/api/v1/accounts/#{account.id}/kanban/account_user_preferences",
            params: {
              preferences: {
                board_filters: {
                  '1' => {
                    agent_id: 'all'
                  }
                }
              }
            },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
