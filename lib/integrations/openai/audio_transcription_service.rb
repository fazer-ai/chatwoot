# Transcribes an audio attachment with the account's OpenAI integration key, on an agent's request,
# and stores the text in `meta.transcribed_text`, which the audio bubble already shows.
#
# The Enterprise Llm::SpeechToTextService does the same call, but it transcribes every voice note
# automatically on Captain's installation key and credits, and it is stripped from CE images.
class Integrations::Openai::AudioTranscriptionService
  # OpenAI's limit is 25 MB decimal, not 25.megabytes.
  BYTE_LIMIT = 25_000_000
  # OpenAI picks the decoder from the file name, and rejects `.oga` even when the bytes are Ogg.
  EXTENSION_ALIASES = { 'oga' => 'ogg', 'x-m4a' => 'm4a', 'x-wav' => 'wav', 'mpeg' => 'mp3' }.freeze

  pattr_initialize [:attachment!]

  def self.transcribable?(attachment)
    attachment.audio? &&
      attachment.file.attached? &&
      attachment.meta['transcribed_text'].blank? &&
      attachment.file.blob.byte_size <= BYTE_LIMIT
  end

  def perform
    return unless self.class.transcribable?(attachment)
    # The integration can be turned off between the request and the job.
    return if openai_hook.blank?

    text = transcribe
    return if text.blank?

    attachment.update!(meta: attachment.meta.merge('transcribed_text' => text))
    message = attachment.message
    message.send_update_event
    message.reindex if ChatwootApp.advanced_search_allowed?
  end

  private

  def openai_hook
    @openai_hook ||= attachment.account.hooks.find_by(app_id: 'openai', status: 'enabled')
  end

  def transcribe
    with_audio_file do |file|
      # temperature 0 keeps the model from inventing repeated phrases over silence.
      response = client.audio.transcribe(parameters: { model: model, file: file, temperature: 0.0 })
      response['text']
    end
  end

  def client
    OpenAI::Client.new(
      access_token: openai_hook.settings['api_key'],
      uri_base: InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com/'
    )
  end

  def model
    Llm::FeatureRouter.resolve(feature: 'audio_transcription', account: attachment.account)[:model]
  end

  def with_audio_file
    blob = attachment.file.blob
    Tempfile.create(['audio-transcription', ".#{file_extension(blob)}"], binmode: true) do |file|
      blob.download { |chunk| file.write(chunk) }
      file.rewind
      yield file
    end
  end

  def file_extension(blob)
    extension = blob.filename.extension_without_delimiter.presence || blob.content_type.split(';').first.split('/').last
    extension = extension.downcase
    EXTENSION_ALIASES.fetch(extension, extension)
  end
end
