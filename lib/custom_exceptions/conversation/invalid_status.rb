# frozen_string_literal: true

# The status a caller sends when creating a conversation is read now, so a value the enum cannot
# take is an answer to the caller rather than a crash: it used to reach the assignment and raise
# `ArgumentError`, which the API returns as a 500.
class CustomExceptions::Conversation::InvalidStatus < CustomExceptions::Base
  def message
    I18n.t('errors.conversations.invalid_status', status: @data[:status], statuses: @data[:statuses].join(', '))
  end

  def http_status
    422
  end
end
