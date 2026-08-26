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

      # The four event shapes this endpoint can produce, pinned together so no reordering can change
      # one without showing up here. What every row has in common is the point: the origin a consumer
      # reads is the NEW one, on every event either path emits.
      it 'names the new origin on every event it emits, whichever path ran' do
        agent_bot = create(:agent_bot, account: account, outgoing_url: 'https://bot.test/hook')
        create(:agent_bot_inbox, inbox: web_widget.inbox, agent_bot: agent_bot, account: account)

        redirect = lambda do |payload|
          seen = []
          allow(AgentBots::WebhookJob).to receive(:perform_later) { |_url, pl, *| seen << pl }
          post '/api/v1/widget/redirect_token',
               params: { website_token: web_widget.website_token,
                         token: Widget::RedirectToken.generate({ 'inbox_id' => web_widget.inbox.id,
                                                                 'identifier' => 'user-42' }.merge(payload)) },
               headers: { 'X-Auth-Token' => token }, as: :json
          # Every payload names the pairing, template messages included; the widget's email-collect
          # templates ride along on the first inbound and say nothing about the episode, so the
          # sequence below is the customer-visible one.
          expect(seen.map { |pl| pl[:redirect_origin_display_id] || pl.dig(:conversation, :redirect_origin_display_id) }.uniq)
            .to eq(seen.empty? ? [] : [payload['origin_display_id']].compact.presence || [nil])
          seen.reject { |pl| pl[:message_type] == 'template' }.map do |pl|
            [pl[:event], pl[:redirect_origin_display_id] || pl.dig(:conversation, :redirect_origin_display_id)]
          end
        end

        # A first redirect creates the conversation, so its pairing rides on the creation itself.
        redirect.call('origin_display_id' => 77)

        # Origin changes, cloned message: the update states it, and the message a consumer acts on
        # already carries it.
        expect(redirect.call('origin_display_id' => 91, 'message' => 'oi'))
          .to eq([%w[conversation_updated] << 91, %w[message_created] << 91].map(&:flatten))

        # Origin changes, no message: the update is the only witness there is, which is why the column
        # is in list_of_keys at all.
        expect(redirect.call('origin_display_id' => 77)).to eq([['conversation_updated', 77]])

        # Origin unchanged, cloned message: nothing to state, and the message still names it.
        expect(redirect.call('origin_display_id' => 77, 'message' => 'de novo'))
          .to eq([['message_created', 77]])

        # Origin unchanged, no message: no row changed and no message exists, so there is nothing for
        # an event to say. A repeated link from one WhatsApp conversation lands here.
        expect(redirect.call('origin_display_id' => 77)).to eq([])

        # No origin at all: the pairing is CLEARED, and the clear is announced like any other change.
        # The key is then absent from the payload, the same shape a conversation outside an episode has.
        expect(redirect.call({})).to eq([['conversation_updated', nil]])

        # ...and once it is gone, a second origin-less token has nothing left to clear.
        expect(redirect.call({})).to eq([])
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

      it 'takes the newest origin on re-entry, and a token without one clears it' do
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

        # Consuming a token is the ONE event that sets the pairing, so a token that names no origin
        # leaves the previous one with nothing behind it: the lead came back through a link this
        # instance cannot attribute. Keeping it would hand a consumer that MESSAGES and RESOLVES the
        # named conversation full confidence in a previous episode's answer; clearing it sends that
        # consumer to whatever it does when it has no answer, which is a decision it makes knowingly.
        third = Widget::RedirectToken.generate({ 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42' })
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: third },
             headers: { 'X-Auth-Token' => token }, as: :json
        expect(contact.reload.conversations.last.redirect_origin_display_id).to be_nil
      end

      # And the clear is announced, on the same terms as a change: it moves the column, so it emits
      # its own conversation_updated. A consumer that only ever hears about origins it can act on
      # would keep acting on the one this token just invalidated.
      it 'announces the clear, and stops shipping the key' do
        agent_bot = create(:agent_bot, account: account, outgoing_url: 'https://bot.test/hook')
        create(:agent_bot_inbox, inbox: web_widget.inbox, agent_bot: agent_bot, account: account)
        first = Widget::RedirectToken.generate(
          { 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42', 'origin_display_id' => 77 }
        )
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: first },
             headers: { 'X-Auth-Token' => token }, as: :json

        payloads = []
        allow(AgentBots::WebhookJob).to receive(:perform_later) { |_url, pl, *| payloads << pl }

        second = Widget::RedirectToken.generate({ 'inbox_id' => web_widget.inbox.id, 'identifier' => 'user-42' })
        post '/api/v1/widget/redirect_token',
             params: { website_token: web_widget.website_token, token: second },
             headers: { 'X-Auth-Token' => token }, as: :json

        updated = payloads.find { |pl| pl[:event] == 'conversation_updated' }
        expect(updated).to be_present
        # Absent rather than nil, the same shape a conversation outside an episode has.
        expect(updated).not_to have_key(:redirect_origin_display_id)
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
