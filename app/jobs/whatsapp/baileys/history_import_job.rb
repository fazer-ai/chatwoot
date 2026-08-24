# One chat's slice of a history dump.
#
# Split per chat rather than per frame so a chat locked by live traffic retries on its own
# without holding up the rest of the import, and so a single failure loses one conversation
# instead of the whole weekend.
#
# The boundary is decided before any of these run and handed in, because they run in
# parallel: a worker reading it for itself would measure against whatever the workers that
# went first had already written.
class Whatsapp::Baileys::HistoryImportJob < ApplicationJob
  queue_as :low

  # Live traffic for the same chat holds the same lock, and it is the shorter of the two:
  # waiting is the right answer, and the budget is sized so an import that lands mid-burst
  # still gets its turn.
  retry_on Whatsapp::Session::Inbound::Locks::Busy, wait: 10.seconds, attempts: 10

  # `announce` defaults for the jobs already queued when this shipped, and for every dump
  # the phone volunteers, which is all of them but the answer to a press.
  def perform(inbox, messages, watermark, requested, announce: false)
    channel = inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'baileys'

    Whatsapp::Baileys::HistoryImporter.new(
      inbox: inbox,
      params: { messages: messages, watermark: watermark, requested: requested, announce: announce }
    ).perform
  end
end
