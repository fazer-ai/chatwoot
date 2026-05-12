require 'rails_helper'

RSpec.describe 'Languages API', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/languages' do
    before do
      Language.delete_all
      create(:language, code: 'pt-br', name: 'Português', position: 1)
      create(:language, code: 'en-us', name: 'Inglês',    position: 2)
      create(:language, code: 'es-es', name: 'Espanhol',  position: 3)
      create(:language, code: 'fr-fr', name: 'Francês',   position: 4)
    end

    it 'returns unauthorized when no token is provided' do
      get '/api/v1/languages'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the languages ordered by position' do
      get '/api/v1/languages', headers: user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      codes = response.parsed_body['data'].pluck('code')
      expect(codes).to eq(%w[pt-br en-us es-es fr-fr])
    end
  end
end
