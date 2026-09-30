# One slice of history, filed off the thread that read it.
#
# The session layer's twin of Whatsapp::Baileys::HistoryImportJob, and it holds itself back
# the same way: an import slot before the chat lock, a batch that finds every slot taken
# waits in the queue nobody reads until a slot is given back, and a chat busy with live
# traffic is waited out on the lock's own budget. Inline on the connector's consumer, a
# pairing dump held the shard for as long as the whole archive took to write, and every
# live event of every session behind it waited that long.
#
# The boundary is read before the job is queued and handed in, because slices run in
# parallel: one reading it for itself would measure against what the slices that went
# first had already written.
class Whatsapp::Session::HistoryImportJob < ApplicationJob
  queue_as :low

  # The same budget as the Baileys job, for the same reason: what a slice waits out on the
  # chat lock is mostly the slices of the same chat queued ahead of it.
  retry_on Whatsapp::Session::Inbound::Locks::Busy, wait: 30.seconds, attempts: 40

  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.info("Skipping #{job.class} because of ActiveJob::DeserializationError (#{error.message})")
    Whatsapp::Session::Inbound::ImportSlots.top_up(into: job.class.queue_name)
  end

  # `messages` are the slice as the contract puts it on the wire. Everything after
  # `requested` says how to file it rather than what is in it, and is collected rather than
  # listed for the reason the Baileys job gives: a job's arguments outlive the deploy that
  # queued them.
  def perform(inbox, messages, watermark, requested, **filing)
    self.queue_name = self.class.queue_name
    channel = inbox&.channel
    return slots.top_up(into: queue_name) unless channel.respond_to?(:session_capabilities)

    held = false
    slots.with_slot do
      held = true
      import(channel, messages, watermark, requested, filing)
    end
  rescue Whatsapp::Session::Inbound::ImportSlots::Full
    retry_job(queue: slots::WAITING_QUEUE)
    slots.top_up(into: self.class.queue_name)
  ensure
    slots.top_up(into: self.class.queue_name) if held
  end

  private

  def slots = Whatsapp::Session::Inbound::ImportSlots

  def import(channel, messages, watermark, requested, filing)
    Whatsapp::Session::Inbound::HistoryImporter.new(
      channel: channel,
      messages: Array(messages).map { |raw| Whatsapp::Session::Model::InboundMessage.from_h(raw) },
      requested: requested, watermark: watermark,
      announce: filing.fetch(:announce, false), group_name: filing[:group_name],
      exhausted: filing[:exhausted] && Whatsapp::Session::Model::Address.from_h(filing[:exhausted])
    ).perform
  end
end
