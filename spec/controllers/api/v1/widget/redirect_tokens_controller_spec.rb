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

    # fazer-ai/agents#222: the two conversations of one redirect episode could not be paired from
    # anything this side stores. The origin rides in the token because the mint is the only moment
    # both halves are known together.
    context 'when the token carries the origin conversation' do
      it 'records it on the widget conversation, as the display_id' do
        redirect_token = Widget::RedirectToken.generate(
          { 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'message' => 'Hello', 'origin_display_id' => 77 }
        )

        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: redirect_token },
             headers: { 'X-Auth-Token' => token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(contact.reload.conversations.last.redirect_origin_display_id).to eq(77)
      end

      it 'ships it to the consumers on push_data, and leaves it out when there is none' do
        redirect_token = Widget::RedirectToken.generate(
          { 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'message' => 'Hello', 'origin_display_id' => 77 }
        )

        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: redirect_token },
             headers: { 'X-Auth-Token' => token },
             as: :json

        redirected = contact.reload.conversations.last
        expect(redirected.push_event_data[:redirect_origin_display_id]).to eq(77)
        # A conversation outside a redirect episode does not carry the key at all.
        expect(create(:conversation, account: account).push_event_data).not_to have_key(:redirect_origin_display_id)
      end

      # The consumer acts on the FIRST event it receives, which is the cloned message. AgentBotListener
      # is on the SYNC dispatcher, so that payload is built inside Message.create!, and the pairing has
      # to be on the row before the message exists. The conversation_updated that follows is a second
      # witness, not a substitute: a consumer that answered the message already used the old pairing.
      it 'is already on the conversation the first webhook payload carries' do
        agent_bot = create(:agent_bot, account: account, outgoing_url: 'https://bot.test/hook')
        create(:agent_bot_inbox, inbox: web_widget.inbox, agent_bot: agent_bot, account: account)
        redirect_token = Widget::RedirectToken.generate(
          { 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'message' => 'Hello', 'origin_display_id' => 77 }
        )

        payloads = []
        allow(AgentBots::WebhookJob).to receive(:perform_later) { |_url, payload, *| payloads << payload }

        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: redirect_token },
             headers: { 'X-Auth-Token' => token },
             as: :json

        message_created = payloads.find { |pl| pl[:event] == 'message_created' }
        expect(message_created).to be_present
        expect(message_created[:conversation][:redirect_origin_display_id]).to eq(77)
      end

      # The message-less resume path (cloneWaMessage off, or a media-only WhatsApp message) writes the
      # pairing onto a conversation that ALREADY exists, so neither a creation event nor a cloned
      # message carries it. Unless that write is observable on its own, a consumer keeps the previous
      # episode's origin and acts on the wrong WhatsApp conversation (fazer-ai/agents#355, round 1).
      it 'emits an event carrying the new origin when a message-less token re-enters a conversation' do
        agent_bot = create(:agent_bot, account: account, outgoing_url: 'https://bot.test/hook')
        create(:agent_bot_inbox, inbox: web_widget.inbox, agent_bot: agent_bot, account: account)

        first = Widget::RedirectToken.generate(
          { 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'origin_display_id' => 77 }
        )
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: first },
             headers: { 'X-Auth-Token' => token }, as: :json

        payloads = []
        allow(AgentBots::WebhookJob).to receive(:perform_later) { |_url, payload, *| payloads << payload }

        second = Widget::RedirectToken.generate(
          { 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'origin_display_id' => 91 }
        )
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: second },
             headers: { 'X-Auth-Token' => token }, as: :json

        updated = payloads.find { |pl| pl[:event] == 'conversation_updated' }
        expect(updated).to be_present
        expect(updated[:redirect_origin_display_id]).to eq(91)
      end

      it 'takes the newest origin on re-entry, and a token without one leaves the old standing' do
        first = Widget::RedirectToken.generate(
          { 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'origin_display_id' => 77 }
        )
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: first },
             headers: { 'X-Auth-Token' => token }, as: :json

        second = Widget::RedirectToken.generate(
          { 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'origin_display_id' => 91 }
        )
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: second },
             headers: { 'X-Auth-Token' => token }, as: :json
        expect(contact.reload.conversations.last.redirect_origin_display_id).to eq(91)

        third = Widget::RedirectToken.generate({ 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42' })
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: third },
             headers: { 'X-Auth-Token' => token }, as: :json
        expect(contact.reload.conversations.last.redirect_origin_display_id).to eq(91)
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
