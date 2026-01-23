require 'rails_helper'

describe '/swagger', type: :request do
  describe 'GET /swagger' do
    it 'redirects to /swagger/' do
      get '/swagger'
      expect(response).to redirect_to('/swagger/')
    end
  end

  describe 'GET /swagger/' do
    it 'renders swagger index.html' do
      get '/swagger/'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('scalar')
      expect(response.body).to include('swagger.json')
    end
  end
end
