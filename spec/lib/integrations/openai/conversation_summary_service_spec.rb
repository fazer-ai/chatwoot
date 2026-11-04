require 'rails_helper'

RSpec.describe Integrations::Openai::ConversationSummaryService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'account-key' })
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'My order never arrived')
    create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'We are checking with the carrier')
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:chat).and_return(
      { 'choices' => [{ 'message' => { 'content' => 'Customer is waiting for a missing order.' } }] }
    )
  end

  describe '#perform' do
    it 'saves the summary as a private note written by the requesting agent' do
      described_class.new(conversation: conversation, user: user).perform

      note = conversation.messages.where(private: true).last
      expect(note).to be_present
      expect(note.content).to include('Customer is waiting for a missing order.')
      expect(note.content).to include(I18n.t('integrations.openai.summary_note_title', locale: account.locale))
      expect(note.sender).to eq(user)
      expect(note.content_attributes['ai_summary']).to be(true)
      expect(OpenAI::Client).to have_received(:new).with(hash_including(access_token: 'account-key'))
    end

    it 'sends the public conversation to OpenAI and keeps private notes out of it' do
      create(:message, account: account, conversation: conversation, private: true, content: 'internal secret')

      described_class.new(conversation: conversation, user: user).perform

      expect(openai_client).to have_received(:chat) do |parameters:|
        transcript = parameters[:messages].last[:content]
        expect(transcript).to include('Customer: My order never arrived')
        expect(transcript).to include('Agent: We are checking with the carrier')
        expect(transcript).not_to include('internal secret')
      end
    end

    it 'does not call OpenAI when the integration was turned off after the request' do
      account.hooks.find_by(app_id: 'openai').update!(status: 'disabled')

      described_class.new(conversation: conversation, user: user).perform

      expect(openai_client).not_to have_received(:chat)
      expect(conversation.messages.where(private: true)).to be_empty
    end

    it 'does not create a note when OpenAI returns no summary' do
      allow(openai_client).to receive(:chat).and_return({ 'choices' => [] })

      described_class.new(conversation: conversation, user: user).perform

      expect(conversation.messages.where(private: true)).to be_empty
    end
  end

  describe '.summarizable?' do
    it 'is false for a conversation without public messages' do
      empty_conversation = create(:conversation, account: account)

      expect(described_class.summarizable?(empty_conversation)).to be(false)
    end

    it 'is true when the conversation has public messages' do
      expect(described_class.summarizable?(conversation)).to be(true)
    end
  end
end
