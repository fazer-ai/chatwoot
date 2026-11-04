class Integrations::Openai::ConversationSummaryJob < ApplicationJob
  queue_as :low

  # A revoked key, or a request OpenAI rejects, does not get better on retry.
  discard_on Faraday::UnauthorizedError, Faraday::BadRequestError do |job, error|
    conversation = job.arguments.first
    Rails.logger.warn("Discarding OpenAI conversation summary for conversation #{conversation&.id}: #{error.class} #{error.response&.dig(:status)}")
  end

  def perform(conversation, user)
    Integrations::Openai::ConversationSummaryService.new(conversation: conversation, user: user).perform
  end
end
