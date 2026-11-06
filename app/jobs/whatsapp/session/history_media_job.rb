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

  # `requeue` asks the drain to first collect the pending files the consent covers, for
  # when it has just grown (Whatsapp::Session::HistoryMedia.requeue). It is a flag of its
  # own and not an argument of the run: a drain already queued or running would otherwise
  # swallow the request, and the files the change just covered would never be queued.
  def self.kick(inbox, wait: nil, requeue: false)
    Redis::Alfred.set(requeue_key(inbox), SecureRandom.uuid, ex: SCHEDULED_TTL.to_i) if requeue
    return unless Redis::Alfred.set(scheduled_key(inbox), '1', nx: true, ex: SCHEDULED_TTL.to_i)

    set(wait: wait).perform_later(inbox)
  end

  def self.scheduled_key(inbox) = "WHATSAPP::HISTORY_MEDIA_SCHEDULED::#{inbox.id}"
  def self.requeue_key(inbox) = "WHATSAPP::HISTORY_MEDIA_REQUEUE::#{inbox.id}"

  def perform(inbox)
    @inbox = inbox
    Redis::Alfred.expire(self.class.scheduled_key(inbox), SCHEDULED_TTL.to_i)
    return finish unless enabled?

    rescan
    drain
  end

  private

  attr_reader :inbox

  def history_media = Whatsapp::Session::HistoryMedia
  def queue_key = history_media.queue_key(inbox)

  # The request is cleared only once the collection went through, so a worker that stops
  # halfway leaves it for the next run, and only if it is still the one this run read: one
  # asked for while collecting is for files this pass may have missed.
  def rescan
    request = Redis::Alfred.get(self.class.requeue_key(inbox))
    return if request.nil?

    history_media.requeue(inbox)
    Redis::Alfred.delete_if_equals(self.class.requeue_key(inbox), request)
  end

  # Read from the database, not from the channel loaded with the job: a batch takes
  # minutes, and an operator who turns the option off or narrows the window in the middle
  # of one expects it to stop at the next file, not twenty files later.
  def enabled?
    history_media.enabled?(inbox.channel.reload.provider_config)
  end

  # The file leaves the queue once it has been dealt with, not when it is picked: a worker
  # that stops in the middle of a download hands the job back, and the next run starts
  # with the same file instead of leaving it pending with nothing to ask for it.
  def drain
    BATCH.times do
      return finish unless enabled?

      id = newest
      return finish if id.nil?

      fetch(Message.find_by(id: id))
      Redis::Alfred.with { |conn| conn.zrem(queue_key, id) }
    end
    self.class.set(wait: 0).perform_later(inbox)
  rescue *TRANSIENT => e
    Rails.logger.warn("[WHATSAPP SESSION] history media of inbox ##{inbox.id} paused: #{e.message}")
    self.class.set(wait: UNAVAILABLE_WAIT).perform_later(inbox)
  end

  def newest = Redis::Alfred.with { |conn| conn.zrevrange(queue_key, 0, 0) }.first

  # The window is read again here and not only when the file was queued: a dump takes
  # hours to work through, and an operator may have narrowed it in between.
  #
  # Anything the provider did not cause is this file's alone: it is reported and left
  # pending, where the button can still ask for it, and the drain moves on. Kept at the
  # head of the queue, it would stop every file behind it for good.
  def fetch(message)
    return if message.nil? || !history_media.pending?(message)
    return if message.created_at < history_media.cutoff(inbox.channel)

    history_media.fetch(message)
  rescue *TRANSIENT
    raise
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: inbox.account).capture_exception
  end

  # Cleared before looking again, so a file queued or a rescan asked for between the last
  # look and this line either sees the flag gone and kicks its own run, or is found here.
  def finish
    Redis::Alfred.delete(self.class.scheduled_key(inbox))
    pending = Redis::Alfred.zcard(queue_key).positive? || Redis::Alfred.exists?(self.class.requeue_key(inbox))
    self.class.kick(inbox) if pending && enabled?
  end
end
