require 'rails_helper'

RSpec.describe 'Api::V1::Widget::RedirectTokensController', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:auth_payload) { { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id } }
  let(:token) { Widget::TokenService.new(payload: auth_payload).generate_token }

  describe 'POST /api/v1/widget/redirect_token' do
    context 'with an invalid redirect token' do
      it 'returns not found' do
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: 'does-not-exist' },
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('invalid_token')
      end
    end

    context 'with a valid redirect token carrying a message' do
      let(:redirect_token) do
        Widget::RedirectToken.generate({ 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'message' => 'Hello' })
      end

      it 'identifies the contact, verifies the inbox and injects the message' do
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: redirect_token },
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['conversation_id']).to be_present
        # The existing session keeps its auth token when the identity does not change.
        expect(body['widget_auth_token']).to be_nil

        expect(contact.reload.identifier).to eq('user-42')
        expect(contact_inbox.reload.hmac_verified).to be(true)

        conversation = contact.conversations.last
        expect(conversation.messages.where(message_type: :incoming).last.content).to eq('Hello')
      end

      it 'consumes the token so it cannot be reused' do
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: redirect_token },
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(Widget::RedirectToken.consume(redirect_token)).to be_nil
      end
    end

    context 'when the session contact is already identified with a different identifier' do
      let(:contact) { create(:contact, account: account, identifier: 'someone-else') }

      it 'issues a fresh widget auth token for the redirected identity' do
        redirect_token = Widget::RedirectToken.generate({ 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42' })

        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: redirect_token },
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['widget_auth_token']).to be_present
      end
    end

    context 'when the token was minted for a different inbox' do
      it 'rejects the token as invalid' do
        other_widget = create(:channel_widget, account: account)
        foreign_token = Widget::RedirectToken.generate({ 'inbox_id' => other_widget.inbox.id, 'identifier' => 'user-42' })

        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: foreign_token },
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('invalid_token')
      end
    end

    context 'when the token carries no identifier and the session contact is already identified' do
      let(:contact) { create(:contact, account: account, identifier: 'existing-id') }

      it 'keeps the existing identified session' do
        redirect_token = Widget::RedirectToken.generate({ 'inbox_id' => web_widget.inbox.id, 'message' => 'Hello again' })

        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: redirect_token },
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['widget_auth_token']).to be_nil
        expect(contact.reload.identifier).to eq('existing-id')
        expect(contact.contact_inboxes.count).to eq(1)
      end
    end
  end
end
