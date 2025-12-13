# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::BoardConversations' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:board) { create(:kanban_board, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/kanban/boards/#{board.id}/conversations" }

  before { account.enable_features('kanban') }

  describe 'GET /api/v1/accounts/:account_id/kanban/boards/:board_id/conversations' do
    context 'when board has no assigned inboxes' do
      it 'returns empty payload' do
        get base_path, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['payload']).to eq([])
      end
    end

    context 'when board has assigned inboxes' do
      before do
        create(:kanban_board_inbox, board: board, inbox: inbox)
      end

      it 'returns conversations from board inboxes' do
        contact = create(:contact, account: account)
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact)

        get base_path, headers: headers

        expect(response).to have_http_status(:ok)
        payload = response.parsed_body['payload']
        expect(payload.size).to eq(1)
        expect(payload.first['id']).to eq(conversation.id)
        expect(payload.first['display_id']).to eq(conversation.display_id)
        expect(payload.first.dig('inbox', 'id')).to eq(inbox.id)
        expect(payload.first.dig('contact', 'id')).to eq(contact.id)
      end

      it 'does not return conversations from other inboxes' do
        other_inbox = create(:inbox, account: account)
        create(:conversation, account: account, inbox: other_inbox, contact: create(:contact, account: account))
        contact = create(:contact, account: account)
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact)

        get base_path, headers: headers

        expect(response).to have_http_status(:ok)
        payload = response.parsed_body['payload']
        expect(payload.size).to eq(1)
        expect(payload.first['id']).to eq(conversation.id)
      end

      it 'filters conversations by search query' do
        contact1 = create(:contact, account: account, name: 'John Doe')
        contact2 = create(:contact, account: account, name: 'Jane Smith')
        conversation1 = create(:conversation, account: account, inbox: inbox, contact: contact1)
        create(:conversation, account: account, inbox: inbox, contact: contact2)

        get base_path, params: { q: 'John' }, headers: headers

        expect(response).to have_http_status(:ok)
        payload = response.parsed_body['payload']
        expect(payload.size).to eq(1)
        expect(payload.first['id']).to eq(conversation1.id)
      end

      it 'searches by display_id' do
        contact = create(:contact, account: account)
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact)

        get base_path, params: { q: conversation.display_id.to_s }, headers: headers

        expect(response).to have_http_status(:ok)
        payload = response.parsed_body['payload']
        expect(payload.size).to eq(1)
        expect(payload.first['id']).to eq(conversation.id)
      end

      it 'searches by contact email' do
        contact = create(:contact, account: account, email: 'test@example.com')
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact)

        get base_path, params: { q: 'test@example' }, headers: headers

        expect(response).to have_http_status(:ok)
        payload = response.parsed_body['payload']
        expect(payload.size).to eq(1)
        expect(payload.first['id']).to eq(conversation.id)
      end

      it 'returns paginated results' do
        contact = create(:contact, account: account)
        25.times { create(:conversation, account: account, inbox: inbox, contact: contact) }

        get base_path, headers: headers

        expect(response).to have_http_status(:ok)
        payload = response.parsed_body['payload']
        meta = response.parsed_body['meta']

        expect(payload.size).to eq(20)
        expect(meta['count']).to eq(25)
        expect(meta['current_page']).to eq(1)
        expect(meta['total_pages']).to eq(2)
      end

      it 'returns second page when requested' do
        contact = create(:contact, account: account)
        25.times { create(:conversation, account: account, inbox: inbox, contact: contact) }

        get base_path, params: { page: 2 }, headers: headers

        expect(response).to have_http_status(:ok)
        payload = response.parsed_body['payload']
        meta = response.parsed_body['meta']

        expect(payload.size).to eq(5)
        expect(meta['current_page']).to eq(2)
      end
    end

    context 'when user is not authorized' do
      let(:agent) { create(:user, account: account) }
      let(:agent_headers) { agent.create_new_auth_token }

      it 'returns not found when user cannot access board' do
        get base_path, headers: agent_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
