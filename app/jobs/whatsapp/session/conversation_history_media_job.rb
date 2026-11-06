# Asks for every history file one conversation is still missing, whatever its age.
#
# What the "download this conversation's files" action queues: somebody needs the context
# of one chat, often an old group, which the inbox's window leaves out on purpose. One file
# at a time, like the inbox's drain, so a large group does not flood the
# provider; a file that is already there or was given up on is skipped by `pending?`, so a
# second press only asks for what the first did not get.
class Whatsapp::Session::ConversationHistoryMediaJob < ApplicationJob
  queue_as :low

  retry_on Down::Error, Whatsapp::Session::Errors::ProviderUnavailable, wait: :polynomially_longer, attempts: 3

  def perform(conversation)
    conversation.messages.where.missing(:attachments).find_each(order: :desc) do |message|
      Whatsapp::Session::HistoryMedia.fetch(message) if Whatsapp::Session::HistoryMedia.pending?(message)
    end
  end
end
