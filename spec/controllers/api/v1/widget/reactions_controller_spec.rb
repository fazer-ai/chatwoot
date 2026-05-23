require 'rails_helper'

RSpec.describe 'Api::V1::Widget::Reactions', type: :request do
  let(:account) { create(:account) }
  let(:channel) { account.simulator_channels.first }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) do
    create(:contact_inbox, contact: contact, inbox: inbox)
  end
  let(:conversation) do
    create(:conversation, contact: contact, inbox: inbox, contact_inbox: contact_inbox, account: account)
  end
  let(:agent_message) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, content: 'Olá')
  end
  let(:auth_payload) { { source_id: contact_inbox.source_id, inbox_id: inbox.id } }
  let(:auth_token) { Widget::TokenService.new(payload: auth_payload).generate_token }
  let(:headers) { { 'X-Auth-Token' => auth_token } }

  describe 'POST /api/v1/widget/messages/:message_id/reactions' do
    it 'creates an incoming reaction message for the contact' do
      target_id = agent_message.id
      expect do
        post "/api/v1/widget/messages/#{target_id}/reactions",
             params: { website_token: channel.website_token, emoji: '👍' },
             headers: headers,
             as: :json
      end.to change(Message, :count).by(1)

      expect(response).to have_http_status(:ok)
      reaction = Message.last
      expect(reaction.content).to eq('👍')
      expect(reaction.message_type).to eq('incoming')
      expect(reaction.sender).to eq(contact)
      expect(reaction.content_attributes['is_reaction']).to be true
      expect(reaction.content_attributes['in_reply_to']).to eq(agent_message.id)
    end

    it 'updates the existing reaction in place on a second emoji' do
      post "/api/v1/widget/messages/#{agent_message.id}/reactions",
           params: { website_token: channel.website_token, emoji: '👍' },
           headers: headers,
           as: :json

      expect do
        post "/api/v1/widget/messages/#{agent_message.id}/reactions",
             params: { website_token: channel.website_token, emoji: '❤️' },
             headers: headers,
             as: :json
      end.not_to change(Message, :count)

      expect(Message.last.content).to eq('❤️')
    end

    it 'soft-deletes the reaction when the same emoji is re-sent' do
      post "/api/v1/widget/messages/#{agent_message.id}/reactions",
           params: { website_token: channel.website_token, emoji: '👍' },
           headers: headers,
           as: :json
      reaction_id = Message.last.id

      post "/api/v1/widget/messages/#{agent_message.id}/reactions",
           params: { website_token: channel.website_token, emoji: '👍' },
           headers: headers,
           as: :json

      reaction = Message.find(reaction_id)
      expect(reaction.content).to eq('')
      expect(reaction.content_attributes['deleted']).to be true
    end

    it 'rejects payloads that are not single emoji' do
      post "/api/v1/widget/messages/#{agent_message.id}/reactions",
           params: { website_token: channel.website_token, emoji: 'not-an-emoji' },
           headers: headers,
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects an empty emoji when no reaction is active' do
      post "/api/v1/widget/messages/#{agent_message.id}/reactions",
           params: { website_token: channel.website_token, emoji: '' },
           headers: headers,
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 404 when the message belongs to a different contact_inbox' do
      other_contact = create(:contact, account: account)
      other_inbox = create(:contact_inbox, contact: other_contact, inbox: inbox)
      other_message = create(
        :message,
        conversation: create(:conversation, contact: other_contact, contact_inbox: other_inbox, inbox: inbox, account: account),
        account: account,
        inbox: inbox,
        message_type: :outgoing
      )

      post "/api/v1/widget/messages/#{other_message.id}/reactions",
           params: { website_token: channel.website_token, emoji: '👍' },
           headers: headers,
           as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when the inbox channel does not support reactions' do
      web_widget = create(:channel_widget, account: account)
      web_contact_inbox = create(:contact_inbox, contact: contact, inbox: web_widget.inbox)
      web_convo = create(:conversation, contact: contact, contact_inbox: web_contact_inbox, inbox: web_widget.inbox, account: account)
      web_message = create(:message, conversation: web_convo, account: account, inbox: web_widget.inbox, message_type: :outgoing)

      web_auth = Widget::TokenService.new(payload: { source_id: web_contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token

      post "/api/v1/widget/messages/#{web_message.id}/reactions",
           params: { website_token: web_widget.website_token, emoji: '👍' },
           headers: { 'X-Auth-Token' => web_auth },
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/not supported/i)
    end
  end
end
