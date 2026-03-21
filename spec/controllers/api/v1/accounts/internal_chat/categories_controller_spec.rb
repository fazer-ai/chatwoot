require 'rails_helper'

RSpec.describe 'Internal Chat Categories API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:account_id/internal_chat/categories' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/internal_chat/categories"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns all categories' do
        category = create(:internal_chat_category, account: account, name: 'Engineering')

        get "/api/v1/accounts/#{account.id}/internal_chat/categories",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        names = body.map { |c| c['name'] }
        expect(names).to include('Engineering')
        expect(body.find { |c| c['id'] == category.id }).to be_present
      end

      it 'returns categories in position order' do
        create(:internal_chat_category, account: account, name: 'Second', position: 2)
        create(:internal_chat_category, account: account, name: 'First', position: 1)

        get "/api/v1/accounts/#{account.id}/internal_chat/categories",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        names = body.map { |c| c['name'] }
        first_idx = names.index('First')
        second_idx = names.index('Second')
        expect(first_idx).to be < second_idx
      end

      it 'includes channels_count in response' do
        category = create(:internal_chat_category, account: account, name: 'Dev')
        create(:internal_chat_channel, :public_channel, account: account, category: category)

        get "/api/v1/accounts/#{account.id}/internal_chat/categories",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.first['channels_count']).to eq(1)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/internal_chat/categories' do
    let(:valid_params) { { category: { name: 'Engineering', position: 1 } } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/internal_chat/categories",
             params: valid_params, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/internal_chat/categories",
             params: valid_params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'creates a new category' do
        post "/api/v1/accounts/#{account.id}/internal_chat/categories",
             params: valid_params,
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['name']).to eq('Engineering')
        expect(body['position']).to eq(1)
        expect(body['account_id']).to eq(account.id)
      end

      it 'returns error for missing name' do
        post "/api/v1/accounts/#{account.id}/internal_chat/categories",
             params: { category: { name: '' } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/internal_chat/categories/:id' do
    let!(:category) { create(:internal_chat_category, account: account, name: 'Old Name') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/categories/#{category.id}",
              params: { category: { name: 'New Name' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/categories/#{category.id}",
              params: { category: { name: 'New Name' } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'updates the category' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/categories/#{category.id}",
              params: { category: { name: 'New Name' } },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['name']).to eq('New Name')
      end

      it 'updates the category position' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/categories/#{category.id}",
              params: { category: { position: 5 } },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['position']).to eq(5)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/internal_chat/categories/:id' do
    let!(:category) { create(:internal_chat_category, account: account, name: 'To Delete') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/categories/#{category.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/categories/#{category.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'destroys the category' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/categories/#{category.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(InternalChat::Category.find_by(id: category.id)).to be_nil
      end
    end
  end
end
