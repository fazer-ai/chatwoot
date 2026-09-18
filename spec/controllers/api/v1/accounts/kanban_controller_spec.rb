require 'rails_helper'

RSpec.describe 'Kanban API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let!(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: create(:contact, account: account, name: 'Maria', phone_number: '+5511999999999')
    )
  end
  let!(:hidden_conversation) { create(:conversation, account: account, inbox: other_inbox) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe 'GET /api/v1/accounts/:account_id/kanban' do
    it 'requires authentication' do
      get "/api/v1/accounts/#{account.id}/kanban"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns only conversations visible to the agent and defaults them to new leads' do
      get "/api/v1/accounts/#{account.id}/kanban", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.dig('kanban_data', 'novo_lead').pluck('id')).to eq([conversation.display_id])
      expect(body.values.to_s).not_to include(hidden_conversation.display_id.to_s)
    end

    it 'filters by contact name without treating wildcard characters as SQL wildcards' do
      get "/api/v1/accounts/#{account.id}/kanban",
          params: { search: '%' },
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('stats', 'total')).to eq(0)
    end
  end

  describe 'PUT /api/v1/accounts/:account_id/kanban/:id/move' do
    it 'moves a visible conversation and preserves its other custom attributes' do
      conversation.update!(custom_attributes: { 'source' => 'campaign' })

      put "/api/v1/accounts/#{account.id}/kanban/#{conversation.display_id}/move",
          params: { status: 'qualificado' },
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.custom_attributes).to eq('source' => 'campaign', 'kanban_status' => 'qualificado')
    end

    it 'rejects an unknown status' do
      put "/api/v1/accounts/#{account.id}/kanban/#{conversation.display_id}/move",
          params: { status: 'unknown' },
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.reload.custom_attributes).not_to have_key('kanban_status')
    end

    it 'does not move a conversation from an inbox the agent cannot access' do
      put "/api/v1/accounts/#{account.id}/kanban/#{hidden_conversation.display_id}/move",
          params: { status: 'qualificado' },
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
