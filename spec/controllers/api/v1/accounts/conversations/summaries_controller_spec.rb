require 'rails_helper'

RSpec.describe 'Conversation Summary API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:summary_url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/summary" }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'I need help')
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:conversation_id/summary' do
    context 'when the account has the OpenAI integration' do
      before { create(:integrations_hook, :openai, account: account) }

      it 'enqueues the summary for the requesting agent' do
        expect do
          post summary_url, headers: agent.create_new_auth_token, as: :json
        end.to have_enqueued_job(Integrations::Openai::ConversationSummaryJob).with(conversation, agent)

        expect(response).to have_http_status(:accepted)
      end

      it 'refuses a conversation with no messages to summarize' do
        empty_conversation = create(:conversation, account: account, inbox: inbox)

        post "/api/v1/accounts/#{account.id}/conversations/#{empty_conversation.display_id}/summary",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Integrations::Openai::ConversationSummaryJob).not_to have_been_enqueued
      end

      it 'refuses an agent outside the inbox' do
        outsider = create(:user, account: account, role: :agent)

        post summary_url, headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the account has no OpenAI integration' do
      it 'refuses the request' do
        post summary_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('OpenAI integration is not enabled')
        expect(Integrations::Openai::ConversationSummaryJob).not_to have_been_enqueued
      end
    end
  end
end
