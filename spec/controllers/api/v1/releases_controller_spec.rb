require 'rails_helper'

RSpec.describe 'Releases API', type: :request do
  let(:account) { create(:account) }
  let(:agent)   { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/releases' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get '/api/v1/releases'
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      let(:fake_releases) do
        [
          { 'tag' => 'v1.2.0', 'published_at' => '2026-05-08T00:00:00Z',
            'url' => 'https://example.test/v1.2.0',
            'notes' => { 'en' => 'EN body', 'pt_BR' => 'Corpo em PT' } },
          { 'tag' => 'v1.1.0', 'published_at' => '2026-04-30T00:00:00Z',
            'url' => 'https://example.test/v1.1.0',
            'notes' => { 'en' => 'Older EN', 'pt_BR' => 'PT mais antigo' } }
        ]
      end

      before do
        allow(Release::CatalogService).to receive(:all).and_return(fake_releases)
      end

      it 'returns the catalog newest first with bilingual notes' do
        get '/api/v1/releases', headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body['data']
        expect(body.size).to eq(2)
        expect(body.first['tag']).to eq('v1.2.0')
        expect(body.first['notes']['en']).to eq('EN body')
        expect(body.first['notes']['pt_BR']).to eq('Corpo em PT')
      end
    end
  end
end
