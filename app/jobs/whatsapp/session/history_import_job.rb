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

  # Who the slice was read from, which the job reads back before writing: while it waited
  # the inbox may have moved to another provider, or been pointed at another instance or
  # session of the same one, and a pile from the previous account filed here would be
  # somebody else's conversations. The dispatcher asks the same question of an event;
  # this is the same event arriving late.
  def self.identity(channel)
    [channel.provider, Whatsapp::Session::Registry.instance_fingerprint(channel) || channel.provider_config&.dig('session_id')]
  end

  # `messages` are the slice as the contract puts it on the wire. Everything after
  # `requested` says how to file it rather than what is in it, and is collected rather than
  # listed for the reason the Baileys job gives: a job's arguments outlive the deploy that
  # queued them.
  def perform(inbox, messages, watermark, requested, **filing)
    self.queue_name = self.class.queue_name
    channel = inbox&.channel
    # Dropped without taking a slot, so it gives none back: the batch behind it is woken
    # here or it waits for the sweep.
    return slots.top_up(into: queue_name) unless same_account?(channel, filing[:identity])

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

  def same_account?(channel, identity)
    return false unless channel.is_a?(Channel::Whatsapp) && Whatsapp::Session::Registry.session_provider?(channel.provider)

    identity.nil? || Array(identity) == self.class.identity(channel)
  end

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
