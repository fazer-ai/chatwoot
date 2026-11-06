# Asks for every history file one conversation is still missing, whatever its age.
#
# What the "download this conversation's files" action queues: somebody needs the context
# of one chat, often an old group, which the inbox's window leaves out on purpose. One file
# at a time, like the inbox's drain, so a large group does not flood the
# provider; a file that is already there or was given up on is skipped by `pending?`, so a
# second press only asks for what the first did not get.
class Whatsapp::Session::ConversationHistoryMediaJob < ApplicationJob
  queue_as :low

  retry_on(*Whatsapp::Session::HistoryMediaJob::TRANSIENT, wait: :polynomially_longer, attempts: 3)

  # Downloads per run. An old group can hold thousands of files, and one run holding a
  # worker for all of them is what the inbox's drain already avoids: each run takes a batch
  # and hands the rest to the next one.
  BATCH = Whatsapp::Session::HistoryMediaJob::BATCH

  def perform(conversation, before_id = nil)
    fetched = 0
    scope = conversation.messages.where.missing(:attachments)
    scope = scope.where(id: ..before_id) if before_id
    scope.find_each(order: :desc) do |message|
      next unless Whatsapp::Session::HistoryMedia.pending?(message)
      return self.class.perform_later(conversation, message.id) if fetched == BATCH

      Whatsapp::Session::HistoryMedia.fetch(message)
      fetched += 1
    end
  end
end
