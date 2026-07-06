require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RedirectTokensController', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:web_widget) { create(:channel_widget, account: account) }

  describe 'POST /api/v1/accounts/{account.id}/redirect_tokens' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/redirect_tokens",
             params: { inbox_id: web_widget.inbox.id, identifier: 'user-1' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'mints a redirect token for a web widget inbox' do
        post "/api/v1/accounts/#{account.id}/redirect_tokens",
             headers: agent.create_new_auth_token,
             params: { inbox_id: web_widget.inbox.id, identifier: 'user-1', message: 'Hi' },
             as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['token']).to be_present
        expect(body['expires_in']).to eq(Widget::RedirectToken::DEFAULT_TTL)
        expect(body['website_url']).to eq(web_widget.website_url)
        expect(Widget::RedirectToken.consume(body['token'])).to eq('identifier' => 'user-1', 'message' => 'Hi')
      end

      it 'honours a custom ttl_seconds' do
        post "/api/v1/accounts/#{account.id}/redirect_tokens",
             headers: agent.create_new_auth_token,
             params: { inbox_id: web_widget.inbox.id, identifier: 'user-1', ttl_seconds: 60 },
             as: :json

        expect(response.parsed_body['expires_in']).to eq(60)
      end

      it 'omits blank optional attributes from the stored payload' do
        post "/api/v1/accounts/#{account.id}/redirect_tokens",
             headers: agent.create_new_auth_token,
             params: { inbox_id: web_widget.inbox.id, identifier: 'user-1' },
             as: :json

        token = response.parsed_body['token']
        expect(Widget::RedirectToken.consume(token)).to eq('identifier' => 'user-1')
      end

      it 'rejects a non web widget inbox' do
        email_inbox = create(:channel_email, account: account).inbox

        post "/api/v1/accounts/#{account.id}/redirect_tokens",
             headers: agent.create_new_auth_token,
             params: { inbox_id: email_inbox.id, identifier: 'user-1' },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('not_a_web_widget')
      end

      it 'returns not found for an inbox from another account' do
        other_widget = create(:channel_widget)

        post "/api/v1/accounts/#{account.id}/redirect_tokens",
             headers: agent.create_new_auth_token,
             params: { inbox_id: other_widget.inbox.id, identifier: 'user-1' },
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
