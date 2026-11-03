require 'rails_helper'

RSpec.describe 'Conversation Message Transcription API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let!(:audio) do
    message.attachments.create!(account: account, file_type: :audio,
                                file: fixture_file_upload(Rails.root.join('spec/assets/sample.mp3'), 'audio/mpeg'))
  end
  let(:transcription_url) do
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/transcription"
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:message_id/transcription' do
    context 'when the account has the OpenAI integration' do
      before { create(:integrations_hook, :openai, account: account) }

      it 'enqueues a transcription for each audio without one' do
        transcribed = message.attachments.create!(account: account, file_type: :audio, meta: { 'transcribed_text' => 'done' },
                                                  file: fixture_file_upload(Rails.root.join('spec/assets/sample.ogg'), 'audio/ogg'))

        expect do
          post transcription_url, headers: agent.create_new_auth_token, as: :json
        end.to have_enqueued_job(Integrations::Openai::AudioTranscriptionJob).with(audio).exactly(:once)

        expect(response).to have_http_status(:accepted)
        expect(Integrations::Openai::AudioTranscriptionJob).not_to have_been_enqueued.with(transcribed)
      end

      it 'refuses a message with nothing left to transcribe' do
        audio.update!(meta: { 'transcribed_text' => 'done' })

        post transcription_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Integrations::Openai::AudioTranscriptionJob).not_to have_been_enqueued
      end

      it 'refuses an agent outside the inbox' do
        outsider = create(:user, account: account, role: :agent)

        post transcription_url, headers: outsider.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the account has no OpenAI integration' do
      it 'refuses the request' do
        post transcription_url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('OpenAI integration is not enabled')
      end
    end
  end
end
