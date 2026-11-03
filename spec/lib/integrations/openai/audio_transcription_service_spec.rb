require 'rails_helper'

RSpec.describe Integrations::Openai::AudioTranscriptionService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:attachment) do
    message.attachments.create!(account: account, file_type: :audio,
                                file: fixture_file_upload(Rails.root.join('spec/assets/sample.mp3'), 'audio/mpeg'))
  end
  let(:audio_client) { instance_double(OpenAI::Audio) }
  let(:openai_client) { instance_double(OpenAI::Client, audio: audio_client) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'account-key' })
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(audio_client).to receive(:transcribe).and_return({ 'text' => 'Olá, tudo bem?' })
  end

  describe '#perform' do
    it 'stores the transcription with the account key and broadcasts the message' do
      allow(message).to receive(:send_update_event)
      allow(attachment).to receive(:message).and_return(message)

      described_class.new(attachment: attachment).perform

      expect(attachment.reload.meta['transcribed_text']).to eq('Olá, tudo bem?')
      expect(OpenAI::Client).to have_received(:new).with(hash_including(access_token: 'account-key'))
      expect(message).to have_received(:send_update_event)
    end

    it 'sends a .ogg file name for an .oga voice note' do
      attachment.file.blob.update!(filename: 'voice.oga')
      described_class.new(attachment: attachment).perform

      expect(audio_client).to have_received(:transcribe) do |parameters:|
        expect(File.extname(parameters[:file].path)).to eq('.ogg')
      end
    end

    it 'keeps the other meta keys' do
      attachment.update!(meta: { 'duration' => 12 })

      described_class.new(attachment: attachment).perform

      expect(attachment.reload.meta).to include('duration' => 12, 'transcribed_text' => 'Olá, tudo bem?')
    end

    it 'does not call OpenAI when the audio already has a transcription' do
      attachment.update!(meta: { 'transcribed_text' => 'already there' })

      described_class.new(attachment: attachment).perform

      expect(audio_client).not_to have_received(:transcribe)
    end

    it 'does not call OpenAI when the integration was turned off after the request' do
      account.hooks.find_by(app_id: 'openai').update!(status: 'disabled')

      described_class.new(attachment: attachment).perform

      expect(audio_client).not_to have_received(:transcribe)
    end
  end

  describe '.transcribable?' do
    it 'refuses audio over the OpenAI size limit' do
      attachment.file.blob.update!(byte_size: described_class::BYTE_LIMIT + 1)

      expect(described_class.transcribable?(attachment)).to be(false)
    end

    it 'refuses attachments that are not audio' do
      image = message.attachments.create!(account: account, file_type: :image,
                                          file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))

      expect(described_class.transcribable?(image)).to be(false)
    end
  end
end
