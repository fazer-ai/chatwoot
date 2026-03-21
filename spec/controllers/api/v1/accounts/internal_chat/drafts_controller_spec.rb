require 'rails_helper'

RSpec.describe 'Internal Chat Drafts API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_chat_channel, :public_channel, account: account, name: 'general') }

  describe 'GET /api/v1/accounts/:account_id/internal_chat/drafts' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/internal_chat/drafts"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns the user drafts' do
        create(:internal_chat_draft, account: account, user: agent, channel: channel, content: 'my draft')

        get "/api/v1/accounts/#{account.id}/internal_chat/drafts",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.length).to eq(1)
        expect(body.first['content']).to eq('my draft')
      end

      it 'does not return drafts from other users' do
        other_agent = create(:user, account: account, role: :agent)
        create(:internal_chat_draft, account: account, user: other_agent, channel: channel, content: 'not mine')

        get "/api/v1/accounts/#{account.id}/internal_chat/drafts",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body).to be_empty
      end

      it 'returns drafts ordered by updated_at descending' do
        channel2 = create(:internal_chat_channel, :public_channel, account: account, name: 'random')
        old_draft = create(:internal_chat_draft, account: account, user: agent, channel: channel,
                                                 content: 'old', updated_at: 2.hours.ago)
        new_draft = create(:internal_chat_draft, account: account, user: agent, channel: channel2,
                                                 content: 'new', updated_at: 1.minute.ago)

        get "/api/v1/accounts/#{account.id}/internal_chat/drafts",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.first['id']).to eq(new_draft.id)
        expect(body.last['id']).to eq(old_draft.id)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/internal_chat/channels/:channel_id/draft' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
              params: { content: 'test' }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'creates a new draft' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
              params: { content: 'my draft content' },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['content']).to eq('my draft content')
        expect(body['internal_chat_channel_id']).to eq(channel.id)
      end

      it 'updates an existing draft' do
        create(:internal_chat_draft, account: account, user: agent, channel: channel, content: 'old content')

        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
              params: { content: 'updated content' },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['content']).to eq('updated content')
      end

      it 'returns unauthorized for a private channel the agent is not a member of' do
        private_channel = create(:internal_chat_channel, :private_channel, account: account, name: 'secret')

        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{private_channel.id}/draft",
              params: { content: 'test' },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a thread draft with parent_id' do
        parent_message = create(:internal_chat_message, account: account, channel: channel, sender: agent)

        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
              params: { content: 'thread reply draft', parent_id: parent_message.id },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['content']).to eq('thread reply draft')
        expect(body['parent_id']).to eq(parent_message.id)
      end

      it 'does not create a duplicate draft, updates existing one for same channel' do
        create(:internal_chat_draft, account: account, user: agent, channel: channel, content: 'old')

        expect do
          patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
                params: { content: 'updated' },
                headers: agent.create_new_auth_token,
                as: :json
        end.not_to change(InternalChat::Draft, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['content']).to eq('updated')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/internal_chat/channels/:channel_id/draft' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'removes the draft' do
        create(:internal_chat_draft, account: account, user: agent, channel: channel, content: 'to delete')

        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:ok)
        expect(InternalChat::Draft.where(user: agent, internal_chat_channel_id: channel.id).count).to eq(0)
      end

      it 'returns not found when no draft exists' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'removes a thread draft when parent_id is provided' do
        parent_message = create(:internal_chat_message, account: account, channel: channel, sender: agent)
        create(:internal_chat_draft, account: account, user: agent, channel: channel, parent: parent_message, content: 'thread draft')

        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
               params: { parent_id: parent_message.id },
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:ok)
        expect(InternalChat::Draft.where(user: agent, internal_chat_channel_id: channel.id, parent_id: parent_message.id).count).to eq(0)
      end

      it 'only removes the targeted draft, not drafts in other channels' do
        channel2 = create(:internal_chat_channel, :public_channel, account: account, name: 'other')
        create(:internal_chat_draft, account: account, user: agent, channel: channel, content: 'draft 1')
        create(:internal_chat_draft, account: account, user: agent, channel: channel2, content: 'draft 2')

        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/draft",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:ok)
        expect(InternalChat::Draft.where(user: agent).count).to eq(1)
        expect(InternalChat::Draft.find_by(user: agent).internal_chat_channel_id).to eq(channel2.id)
      end
    end
  end
end
