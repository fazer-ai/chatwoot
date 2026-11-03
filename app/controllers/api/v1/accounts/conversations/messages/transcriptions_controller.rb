# An agent asks for the voice notes of a message to be transcribed with the account's OpenAI
# integration key. The work runs in a job and the text reaches the bubble with the message's
# update event, the same way the Enterprise automatic transcription does.
class Api::V1::Accounts::Conversations::Messages::TranscriptionsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_openai_integration
  before_action :set_attachments

  def create
    @attachments.each { |attachment| Integrations::Openai::AudioTranscriptionJob.perform_later(attachment) }
    head :accepted
  end

  private

  def ensure_openai_integration
    return if Current.account.hooks.exists?(app_id: 'openai', status: 'enabled')

    render json: { error: 'OpenAI integration is not enabled' }, status: :unprocessable_entity
  end

  def set_attachments
    message = @conversation.messages.find(params[:message_id])
    @attachments = message.attachments.select { |attachment| Integrations::Openai::AudioTranscriptionService.transcribable?(attachment) }
    return if @attachments.any?

    render json: { error: 'Message has no audio to transcribe' }, status: :unprocessable_entity
  end
end
