require 'rails_helper'

RSpec.describe 'Super Admin health score report', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account_one) { create(:account, name: 'Acme') }
  let(:account_two) { create(:account, name: 'Beta') }
  let(:account_three) { create(:account, name: 'Without snapshot') }

  describe 'GET /super_admin/reports/health_score' do
    it 'redirects unauthenticated requests' do
      get '/super_admin/reports/health_score'
      expect(response).to have_http_status(:redirect)
    end

    it 'renders the Vue mount when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/health_score'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('HealthScoreIndex')
    end
  end

  describe 'GET /super_admin/reports/health_score/data' do
    before do
      create(:account_health_score,
             account: account_one,
             score: 72,
             captured_on: Date.current,
             breakdown: {
               'kill_clause' => nil,
               'phase' => 'mature',
               'metrics' => { 'ai_active_rate' => { 'sub_score' => 75, 'missing' => false, 'raw' => {} } },
               'groups' => {
                 'outcomes' => { 'weight_total' => 40, 'sub_score_normalized' => 78, 'missing' => false },
                 'operational' => { 'weight_total' => 25, 'sub_score_normalized' => 100, 'missing' => false },
                 'engagement' => { 'weight_total' => 35, 'sub_score_normalized' => 62, 'missing' => false }
               }
             })
      create(:account_health_score, account: account_two, score: 28, captured_on: Date.current,
                                    breakdown: { 'kill_clause' => 'no_agent_activity', 'phase' => 'mature' })
      account_three # ensure the third (unscored) account exists
    end

    it 'redirects unauthenticated requests' do
      get '/super_admin/reports/health_score/data'
      expect(response).to have_http_status(:redirect)
    end

    it 'returns one row per account, including those without a snapshot' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/health_score/data'

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['accounts'].length).to eq(3)
      expect(body['accounts'].pluck('account_id')).to contain_exactly(account_one.id, account_two.id, account_three.id)
    end

    it 'classifies score into bands and tallies the counts' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/health_score/data'

      body = response.parsed_body
      by_id = body['accounts'].index_by { |a| a['account_id'] }

      expect(by_id[account_one.id]).to include('score' => 72, 'band' => 'green')
      expect(by_id[account_two.id]).to include('score' => 28, 'band' => 'red')
      expect(by_id[account_three.id]).to include('score' => nil, 'band' => nil)

      expect(body['counts']).to include('red' => 1, 'green' => 1, 'unscored' => 1)
    end

    it 'returns the per-group normalized sub-scores for the report table' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/health_score/data'

      row = response.parsed_body['accounts'].find { |a| a['account_id'] == account_one.id }
      expect(row.dig('groups', 'outcomes', 'sub_score_normalized')).to eq(78)
      expect(row.dig('groups', 'operational', 'sub_score_normalized')).to eq(100)
      expect(row.dig('groups', 'engagement', 'sub_score_normalized')).to eq(62)
    end

    it 'surfaces the kill clause when one is in effect' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/health_score/data'

      row = response.parsed_body['accounts'].find { |a| a['account_id'] == account_two.id }
      expect(row['kill_clause']).to eq('no_agent_activity')
    end

    it 'excludes suspended accounts (both scored and unscored)' do
      suspended_with_score = create(:account, name: 'Suspended scored', status: :suspended)
      create(:account_health_score, account: suspended_with_score, score: 90, captured_on: Date.current)
      create(:account, name: 'Suspended unscored', status: :suspended)

      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/reports/health_score/data'

      account_ids = response.parsed_body['accounts'].pluck('account_id')
      expect(account_ids).to contain_exactly(account_one.id, account_two.id, account_three.id)
      expect(account_ids).not_to include(suspended_with_score.id)
    end
  end
end
