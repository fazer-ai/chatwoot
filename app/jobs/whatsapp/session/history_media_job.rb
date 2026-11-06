# Works through an inbox's history files, newest first, one download at a time.
#
# One of these per inbox at most: `kick` queues it only when none is queued or running,
# and it queues itself again while the inbox still has files waiting. So however large
# the dump, an inbox has a single download in flight for its history, and the low queue
# holds one entry for it, behind which the live media on the medium queue never waits.
#
# Each run takes a bounded batch and hands the queue back, so a dump of thousands of files
# does not hold a worker thread for the hours it takes.
class Whatsapp::Session::HistoryMediaJob < ApplicationJob
  queue_as :low

  BATCH = 20
  # Only a backstop for a run that died without clearing it: a live run refreshes it.
  SCHEDULED_TTL = 1.hour
  # The provider could not be reached, or asked us to slow down. The files stay queued and
  # the drain comes back.
  UNAVAILABLE_WAIT = 2.minutes
  TRANSIENT = [Down::Error, Whatsapp::Session::Errors::ProviderUnavailable, Whatsapp::Session::Errors::RateLimited].freeze

  # `requeue` first collects the pending files the consent covers, for when it has just
  # grown (Whatsapp::Session::HistoryMedia.requeue).
  def self.kick(inbox, wait: nil, requeue: false)
    return unless Redis::Alfred.set(scheduled_key(inbox), '1', nx: true, ex: SCHEDULED_TTL.to_i)

    set(wait: wait).perform_later(inbox, requeue)
  end

  def self.scheduled_key(inbox) = "WHATSAPP::HISTORY_MEDIA_SCHEDULED::#{inbox.id}"

  def perform(inbox, requeue = false) # rubocop:disable Style/OptionalBooleanParameter
    @inbox = inbox
    Redis::Alfred.expire(self.class.scheduled_key(inbox), SCHEDULED_TTL.to_i)
    return finish unless history_media.enabled?(inbox.channel.provider_config)

    history_media.requeue(inbox) if requeue
    drain
  end

  private

  attr_reader :inbox

  def history_media = Whatsapp::Session::HistoryMedia
  def queue_key = history_media.queue_key(inbox)

  def drain
    BATCH.times do
      id, = Redis::Alfred.with { |conn| conn.zpopmax(queue_key) }
      return finish if id.nil?

      fetch(Message.find_by(id: id), id)
    end
    self.class.set(wait: 0).perform_later(inbox)
  rescue *TRANSIENT => e
    Rails.logger.warn("[WHATSAPP SESSION] history media of inbox ##{inbox.id} paused: #{e.message}")
    self.class.set(wait: UNAVAILABLE_WAIT).perform_later(inbox)
  end

  # The window is read again here and not only when the file was queued: a dump takes
  # hours to work through, and an operator may have narrowed it in between.
  def fetch(message, id)
    return if message.nil? || !history_media.pending?(message)
    return if message.created_at < history_media.cutoff(inbox.channel)

    history_media.fetch(message)
  rescue *TRANSIENT
    Redis::Alfred.zadd(queue_key, message.created_at.to_f, id)
    raise
  end

  # Cleared before looking again, so a file queued between the last pop and this line
  # either sees the flag gone and kicks its own run, or is found here.
  def finish
    Redis::Alfred.delete(self.class.scheduled_key(inbox))
    self.class.kick(inbox) if Redis::Alfred.zcard(queue_key).positive? && history_media.enabled?(inbox.channel.provider_config)
  end
end
