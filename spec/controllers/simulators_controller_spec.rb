require 'rails_helper'

describe '/simulator', type: :request do
  let(:account) { create(:account) }
  let(:simulator_channel) { account.simulator_channels.first }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: simulator_channel.inbox) }
  let(:payload) { { source_id: contact_inbox.source_id, inbox_id: simulator_channel.inbox.id } }
  let(:token) { Widget::TokenService.new(payload: payload).generate_token }

  describe 'GET /simulator' do
    it 'renders the page correctly when called with the simulator website_token' do
      get simulator_url(website_token: simulator_channel.website_token)
      expect(response).to be_successful
      expect(response.body).not_to include(token)
    end

    it 'renders the page correctly when called with website_token and cw_conversation' do
      get simulator_url(website_token: simulator_channel.website_token, cw_conversation: token)
      expect(response).to be_successful
      expect(response.body).to include(token)
    end

    it 'returns 404 when called without a website_token' do
      get simulator_url
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 if the account is suspended' do
      account.update!(status: :suspended)

      get simulator_url(website_token: simulator_channel.website_token)
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('Account is suspended')
    end

    it 'returns 404 when the website_token belongs to a Channel::WebWidget (not a simulator)' do
      web_widget = create(:channel_widget, account: account)

      get simulator_url(website_token: web_widget.website_token)
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('simulator channel does not exist')
    end

    it 'drops X-Frame-Options so the dashboard iframe can mount the page' do
      get simulator_url(website_token: simulator_channel.website_token)
      expect(response.headers['X-Frame-Options']).to be_nil
    end
  end
end
