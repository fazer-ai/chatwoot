# The recording of a call is an audio attachment on the call's message, so a transcription
# written from outside reaches it by the same route as the transcription of an audio
# message. The call screen reads `calls.transcript`, which only the Captain transcription
# wrote, so the text is copied there too (#822): the external service keeps the contract
# it already has for audio and never needs to know it was a call.
module Enterprise::Api::V1::Accounts::Conversations::AttachmentsController
  private

  # The latest write wins over a transcription already there, Captain's included: this one
  # is an explicit write by an authorized client, and it arrives after Captain's. An empty
  # text is no transcription, and does not take one away.
  def record_transcription
    text = params.dig(:meta, :transcribed_text).to_s
    call = @attachment.message.call if @attachment.audio?
    return if text.blank? || call.blank?

    call.update!(transcript: text)
    @attachment.message.reindex if ChatwootApp.advanced_search_allowed?
  end
end
