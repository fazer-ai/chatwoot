require 'rails_helper'

# A transcription written from outside, by the same route that carries the transcription
# of an audio message, reaches the call the recording belongs to: the call screen reads
# `calls.transcript`, which only the Captain transcription wrote until now (#822).
RSpec.describe 'Conversation Message Attachments API (call recordings)', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:account) { channel.account }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:message) { create(:message, conversation: conversation, account: account, content_type: :voice_call) }
  let(:recording) { message.attachments.create!(account: account, file_type: :audio, file: audio_file) }
  let!(:call) { create(:call, conversation: conversation, message: message, provider: :whatsapp, transcript: 'original') }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def audio_file = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.mp3'), 'audio/mpeg')

  def write_meta(meta, attachment: recording)
    patch api_v1_account_conversation_message_attachment_url(
      account_id: account.id, conversation_id: conversation.display_id, message_id: attachment.message_id, id: attachment.id
    ), params: { meta: meta }, headers: agent.create_new_auth_token, as: :json
  end

  it 'copies the transcription to the call before the message goes out again' do
    seen = nil
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, *args|
      data = args.find { |arg| arg.is_a?(Hash) && arg.key?(:message) }
      seen = Call.find(call.id).transcript if args.first == 'message.updated' && data[:message].id == message.id
      original.call(*args)
    end

    write_meta({ transcribed_text: 'olá, quero remarcar a consulta' })

    expect(response).to have_http_status(:success)
    expect(call.reload.transcript).to eq('olá, quero remarcar a consulta')
    expect(recording.reload.meta['transcribed_text']).to eq('olá, quero remarcar a consulta')
    expect(seen).to eq('olá, quero remarcar a consulta')
  end

  it 'leaves the call alone when the write carries no text' do
    write_meta({ transcribed_text: '' })
    write_meta({ description: 'sem transcrição' })

    expect(response).to have_http_status(:success)
    expect(call.reload.transcript).to eq('original')
  end

  it 'refuses a transcription that is not text, and writes nothing' do
    [false, 42, ['a']].each do |value|
      write_meta({ transcribed_text: value })

      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(call.reload.transcript).to eq('original')
    expect(recording.reload.meta).not_to have_key('transcribed_text')
  end

  it 'writes to no call for an audio message that is not a call' do
    voice_note = create(:message, conversation: conversation, account: account)
    audio = voice_note.attachments.create!(account: account, file_type: :audio, file: audio_file)

    write_meta({ transcribed_text: 'nota de voz do cliente' }, attachment: audio)

    expect(response).to have_http_status(:success)
    expect(audio.reload.meta['transcribed_text']).to eq('nota de voz do cliente')
    expect(call.reload.transcript).to eq('original')
  end

  it 'copies nothing from an attachment of the call that is not its recording' do
    note = message.attachments.create!(account: account, file_type: :file, file: audio_file)

    write_meta({ transcribed_text: 'não é a gravação' }, attachment: note)

    expect(response).to have_http_status(:success)
    expect(call.reload.transcript).to eq('original')
  end

  it 'answers for a call message with no call recorded' do
    call.destroy!

    write_meta({ transcribed_text: 'sem chamada' })

    expect(response).to have_http_status(:success)
    expect(recording.reload.meta['transcribed_text']).to eq('sem chamada')
  end
end
