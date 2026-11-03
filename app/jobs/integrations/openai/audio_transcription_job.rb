class Integrations::Openai::AudioTranscriptionJob < ApplicationJob
  queue_as :low

  # A revoked key, or audio OpenAI cannot decode, does not get better on retry.
  discard_on Faraday::UnauthorizedError, Faraday::BadRequestError do |job, error|
    Rails.logger.warn("Discarding OpenAI audio transcription for #{job.arguments.first&.id}: #{error.class} #{error.response&.dig(:status)}")
  end

  def perform(attachment)
    Integrations::Openai::AudioTranscriptionService.new(attachment: attachment).perform
  end
end
