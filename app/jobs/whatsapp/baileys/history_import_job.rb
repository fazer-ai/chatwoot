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
  #
  # The other holder is this chat's own dump. A mature chat arrives in a dozen frames, each
  # one a separate job filed under the same key, so what a batch waits out is the batches
  # queued ahead of it and not a single hold. Ten ten-second retries covered neither: a
  # group of 8,545 messages lost eleven batches to its own siblings.
  retry_on Whatsapp::Session::Inbound::Locks::Busy, wait: 30.seconds, attempts: 40

  # How long a batch that found every import slot taken waits before looking again. Spread
  # out so a dump of thousands of batches does not come back all at once, and fixed rather
  # than growing: this is a queue, not a failure.
  SLOT_WAIT = (15..30)

  # Everything past `requested` says how to file this dump rather than what is in it, and
  # it is collected rather than listed because the list grows: each entry has to keep a
  # default for the jobs already queued when it shipped, and a job argument list is a
  # serialization contract that outlives the deploy that changed it.
  #
  # `announce` is false for every dump the phone volunteers, which is all of them but the
  # answer to a press. `group_name` is absent for a bridge too old to send it, and then the
  # importer falls back to naming a group by its jid, exactly as before.
  def perform(inbox, messages, watermark, requested, **filing)
    channel = inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'baileys'

    Whatsapp::Session::Inbound::ImportSlots.with_slot do
      Whatsapp::Baileys::HistoryImporter.new(
        inbox: inbox,
        params: {
          messages: messages, watermark: watermark, requested: requested,
          announce: filing.fetch(:announce, false), group_name: filing[:group_name]
        }
      ).perform
    end
  rescue Whatsapp::Session::Inbound::ImportSlots::Full
    # `retry_job` and not `retry_on`: it files the same job for later without touching the
    # per-exception counters, so a batch that waited through a long dump still has the
    # whole chat lock budget above when its turn comes.
    retry_job(wait: rand(SLOT_WAIT).seconds)
  end
end
