require 'rails_helper'

RSpec.describe 'Internal Chat Channel Members API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_chat_channel, :public_channel, account: account, name: 'general') }

  describe 'GET /api/v1/accounts/:account_id/internal_chat/channels/:channel_id/members' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns members of a public channel' do
        create(:internal_chat_channel_member, channel: channel, user: agent)

        get "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.length).to eq(1)
        expect(body.first['user_id']).to eq(agent.id)
        expect(body.first).to have_key('role')
        expect(body.first).to have_key('muted')
        expect(body.first).to have_key('favorited')
        expect(body.first).to have_key('name')
      end

      it 'returns unauthorized for a private channel the agent is not a member of' do
        private_channel = create(:internal_chat_channel, :private_channel, account: account, name: 'secret')

        get "/api/v1/accounts/#{account.id}/internal_chat/channels/#{private_channel.id}/members",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns members of a private channel the agent is a member of' do
        private_channel = create(:internal_chat_channel, :private_channel, account: account, name: 'team')
        create(:internal_chat_channel_member, channel: private_channel, user: agent)

        get "/api/v1/accounts/#{account.id}/internal_chat/channels/#{private_channel.id}/members",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.length).to eq(1)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/internal_chat/channels/:channel_id/members' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members",
             params: { user_id: agent.id }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent without admin role' do
      it 'returns unauthorized' do
        other_agent = create(:user, account: account, role: :agent)

        post "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members",
             params: { user_id: other_agent.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'adds a member to the channel' do
        post "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members",
             params: { user_id: agent.id },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body.first['user_id']).to eq(agent.id)
        expect(body.first['role']).to eq('member')
      end

      it 'adds multiple members at once' do
        other_agent = create(:user, account: account, role: :agent)

        post "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members",
             params: { user_ids: [agent.id, other_agent.id] },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body.length).to eq(2)
        expect(body.map { |m| m['user_id'] }).to contain_exactly(agent.id, other_agent.id)
      end

      it 'does not create duplicate memberships' do
        create(:internal_chat_channel_member, channel: channel, user: agent)

        post "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members",
             params: { user_id: agent.id },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        expect(channel.channel_members.where(user_id: agent.id).count).to eq(1)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/internal_chat/channels/:channel_id/members/:id' do
    let!(:membership) { create(:internal_chat_channel_member, channel: channel, user: agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}",
              params: { muted: true }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is the member themselves' do
      it 'updates muted status' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}",
              params: { muted: true },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['muted']).to be(true)
      end

      it 'updates favorited status' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}",
              params: { favorited: true },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['favorited']).to be(true)
      end
    end

    context 'when it is a different agent (not the member)' do
      let(:other_agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}",
              params: { muted: true },
              headers: other_agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'updates the member' do
        patch "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}",
              params: { muted: true },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['muted']).to be(true)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/internal_chat/channels/:channel_id/members/:id' do
    let!(:membership) { create(:internal_chat_channel_member, channel: channel, user: agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the member removes themselves (leave)' do
      it 'removes the membership' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(InternalChat::ChannelMember.find_by(id: membership.id)).to be_nil
      end
    end

    context 'when it is a different agent (not the member)' do
      let(:other_agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}",
               headers: other_agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'removes the member' do
        delete "/api/v1/accounts/#{account.id}/internal_chat/channels/#{channel.id}/members/#{membership.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(InternalChat::ChannelMember.find_by(id: membership.id)).to be_nil
      end
    end
  end
end
