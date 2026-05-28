require 'rails_helper'

RSpec.describe 'Internal Chat Reactions API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:internal_chat_channel, :public_channel, account: account, name: 'general') }
  let(:message) { create(:internal_chat_message, account: account, channel: channel, sender: agent, content: 'React to me') }

  describe 'POST /api/v1/accounts/:account_id/internal_chat/messages/:message_id/reactions' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/internal_chat/messages/#{message.id}/reactions",
             params: { emoji: '👍' }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'creates a reaction on a public channel message' do
        post "/api/v1/accounts/#{account.id}/internal_chat/messages/#{message.id}/reactions",
             params: { emoji: '👍' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['emoji']).to eq('👍')
        expect(body['user_id']).to eq(agent.id)
        expect(body['internal_chat_message_id']).to eq(message.id)
      end

      it 'creates a reaction with a different emoji' do
        post "/api/v1/accounts/#{account.id}/internal_chat/messages/#{message.id}/reactions",
             params: { emoji: '🎉' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['emoji']).to eq('🎉')
      end

      it 'returns unauthorized for a private channel message the agent is not a member of' do
        private_channel = create(:internal_chat_channel, :private_channel, account: account, name: 'secret')
        private_message = create(:internal_chat_message, account: account, channel: private_channel,
                                                         sender: administrator, content: 'secret msg')

        post "/api/v1/accounts/#{account.id}/internal_chat/messages/#{private_message.id}/reactions",
             params: { emoji: '👍' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'allows reaction on a private channel message when the agent is a member' do
        private_channel = create(:internal_chat_channel, :private_channel, account: account, name: 'team')
        create(:internal_chat_channel_member, channel: private_channel, user: agent)
        private_message = create(:internal_chat_message, account: account, channel: private_channel,
                                                         sender: agent, content: 'team msg')

        post "/api/v1/accounts/#{account.id}/internal_chat/messages/#{private_message.id}/reactions",
             params: { emoji: '👍' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['emoji']).to eq('👍')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/internal_chat/messages/:message_id/reactions/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        reaction = create(:internal_chat_reaction, message: message, user: agent, emoji: '👍')

        delete "/api/v1/accounts/#{account.id}/internal_chat/messages/#{message.id}/reactions/#{reaction.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is the reaction owner' do
      it 'destroys the reaction' do
        reaction = create(:internal_chat_reaction, message: message, user: agent, emoji: '👍')

        delete "/api/v1/accounts/#{account.id}/internal_chat/messages/#{message.id}/reactions/#{reaction.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(InternalChat::Reaction.find_by(id: reaction.id)).to be_nil
      end
    end

    context 'when it is a different agent (not the reaction owner)' do
      let(:other_agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        reaction = create(:internal_chat_reaction, message: message, user: agent, emoji: '👍')

        delete "/api/v1/accounts/#{account.id}/internal_chat/messages/#{message.id}/reactions/#{reaction.id}",
               headers: other_agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'destroys the reaction regardless of ownership' do
        reaction = create(:internal_chat_reaction, message: message, user: agent, emoji: '👍')

        delete "/api/v1/accounts/#{account.id}/internal_chat/messages/#{message.id}/reactions/#{reaction.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(InternalChat::Reaction.find_by(id: reaction.id)).to be_nil
      end
    end
  end
end
