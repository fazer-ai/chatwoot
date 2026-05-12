require 'rails_helper'

RSpec.describe 'Super Admin accounts API', type: :request do
  include ActiveJob::TestHelper

  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }

  describe 'GET /super_admin/accounts' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get '/super_admin/accounts'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/accounts'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('New account')
        expect(response.body).to include(account.name)
      end
    end
  end

  describe 'POST /super_admin/accounts/{account_id}/reset_cache' do
    before do
      create(:label, account: account)
      create(:inbox, account: account)
      create(:team, account: account)
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the list of accounts' do
        expect(account.cache_keys.keys).to contain_exactly(:inbox, :label, :team)
        sign_in(super_admin, scope: :super_admin)

        now_timestamp = (Time.now.utc.to_f * 1000).to_i
        post "/super_admin/accounts/#{account.id}/reset_cache"
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to eq('Cache keys cleared')

        range = now_timestamp..(now_timestamp + 10_000)
        expect(account.reload.cache_keys.values.all? { |v| range.cover?(v.to_i) }).to be(true)
      end
    end
  end

  describe 'PUT /super_admin/accounts/{account_id} (Auris settings section)' do
    let(:params) do
      {
        account: { name: account.name },
        auris_settings: {
          funnel_enabled: '1',
          ai_status_uses_attribute: '1',
          multi_language_ai: '1'
        }
      }
    end

    before { sign_in(super_admin, scope: :super_admin) }

    it 'persists Funnel and AI status toggles to their dedicated columns' do
      account.update!(funnel_enabled: false, ai_status_uses_attribute: false)

      put "/super_admin/accounts/#{account.id}", params: params

      expect(response).to have_http_status(:redirect)
      account.reload
      expect(account.funnel_enabled).to be(true)
      expect(account.ai_status_uses_attribute).to be(true)
    end

    it 'flips the multi_language_ai column' do
      expect(account.multi_language_ai).to be(false)

      put "/super_admin/accounts/#{account.id}", params: params

      expect(response).to have_http_status(:redirect)
      expect(account.reload.multi_language_ai).to be(true)
    end

    it 'turns settings back off when the checkboxes are submitted unchecked' do
      account.update!(funnel_enabled: true, ai_status_uses_attribute: true, multi_language_ai: true)

      put "/super_admin/accounts/#{account.id}",
          params: params.merge(auris_settings: {
                                 funnel_enabled: '0',
                                 ai_status_uses_attribute: '0',
                                 multi_language_ai: '0'
                               })

      account.reload
      expect(account.funnel_enabled).to be(false)
      expect(account.ai_status_uses_attribute).to be(false)
      expect(account.multi_language_ai).to be(false)
    end
  end

  describe 'DELETE /super_admin/accounts/{account_id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/super_admin/accounts/#{account.id}"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'Deletes the account' do
        total_accounts = Account.count
        sign_in(super_admin, scope: :super_admin)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/super_admin/accounts/#{account.id}"
        end

        expect(Account.count).to eq(total_accounts - 1)
      end
    end
  end
end
