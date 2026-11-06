# The files of an imported history, fetched after the messages.
#
# A history dump carries its media without a reference: the connector keeps what it needs
# to download each file and hands it over only when asked, by message id. Nothing asked,
# so every image, audio and document of an archive stayed an empty bubble for good.
#
# Two ways in. The inbox setting is standing consent: every history message whose file is
# missing and that falls inside the window is queued as it is written, and one drain per
# inbox works through the queue newest first. The buttons in the conversation are a single
# act: they ask for one message, or for every pending file of one conversation, whatever
# its age.
#
# The drain is one job per inbox and downloads one file at a time, on the low queue. A
# pairing dump can carry thousands of files, and queuing a MediaFetchJob each would put
# them all on the medium queue in front of the media of the messages arriving live.
module Whatsapp::Session::HistoryMedia
  DEFAULT_WINDOW_DAYS = 30
  FETCH_KEY = 'history_media_fetch'.freeze
  WINDOW_KEY = 'history_media_days'.freeze

  module_function

  # On unless an operator turned it off: the point is that the files arrive with no action
  # from anybody, and an inbox paired before this existed never saved the option.
  # Both read a provider_config, so a change can be compared with what it replaced.
  def enabled?(config)
    config.to_h[FETCH_KEY] != false
  end

  def window_days(config)
    config.to_h[WINDOW_KEY] || DEFAULT_WINDOW_DAYS
  end

  def cutoff(channel)
    window_days(channel.provider_config).days.ago
  end

  # A history message whose file has not come yet and that has not been given up on. The
  # attachment check is what keeps a second request from attaching the file twice.
  def pending?(message)
    attributes = message.content_attributes || {}
    attributes[Whatsapp::Session::Inbound::MessageAttributes::HISTORY_MEDIA].present? &&
      attributes['pending_media'].present? && message.attachments.none?
  end

  # Whether the inbox's standing consent covers this imported message: the switch and the
  # window.
  def wanted?(message)
    channel = message.inbox.channel
    enabled?(channel.provider_config) && message.created_at >= cutoff(channel)
  end

  # Called by the importer for every message it writes. Only what the setting and the
  # window let through is queued, so turning the option off means nothing is asked for.
  def track(message)
    return unless pending?(message) && wanted?(message)

    Redis::Alfred.zadd(queue_key(message.inbox), message.created_at.to_f, message.id)
    Whatsapp::Session::HistoryMediaJob.kick(message.inbox)
  end

  # Where a media fetch goes, on every path that queues one (MessageWriter.fetch_media_for:
  # the write, a redelivery of a stored message, a placeholder recovered). A live
  # message's file is fetched as always. An imported one goes through the inbox's drain
  # like every other history file, with or without a reference and however many times it
  # is delivered again: a job queued straight away would download it even after the
  # operator turned the option off or narrowed the window, which the drain checks before
  # every file. The reference it came with this time is kept for when it is asked for.
  def route(message, inbound, media)
    if message.content_attributes&.dig('imported').blank?
      return Whatsapp::Session::MediaFetchJob.perform_later(message, media.to_h, inbound.chat&.to_h)
    end

    defer(message, inbound)
    track(message)
  end

  # A history file that came with a reference. It is marked the way a reference-less one
  # is, which is what the drain, the button and the conversation action look for, and the
  # reference is kept: it is how the provider finds the file when it is asked for.
  #
  # A card with readable text keeps rendering as a card while its header waits: marked
  # unsupported, it would trade its text and buttons for the placeholder, for good if the
  # header never comes.
  #
  # Under the lock it looks again, since a download may have landed or given up since the
  # caller looked: marking either pending would hide the file or ask for one that is gone.
  def defer(message, inbound)
    media = Whatsapp::Session::Inbound::MessageWriter.media_in(inbound)
    return if media&.ref.blank?

    as_history(message) do
      message.with_lock do
        next if message.attachments.any? || Whatsapp::Session::Inbound::MessageAttributes.given_up?(message)

        message.update!(content_attributes: message.content_attributes.merge(
          'is_unsupported' => (true unless readable_card?(message)), Whatsapp::Session::Inbound::MessageAttributes::HISTORY_MEDIA => true,
          'pending_media' => media.to_h, 'pending_chat' => inbound.chat&.to_h
        ).compact)
      end
    end
  end

  # Any write to an imported message, its file or its bookkeeping, at the level the message
  # was written at: it reaches the open dashboard and nothing else, no bot, webhook or
  # automation. The archive half stays archive, so an old voice note spends no
  # transcription; the gap half, somebody's unread work recovered late, keeps the side
  # effects a live arrival has. Inside an import already, the import's level stands.
  def as_history(message, &)
    return yield if Import::SilentWrite.on?

    Import::SilentWrite.wrap(announce: true, archive: message.content_attributes['history_archive'].present?, &)
  end

  # A card whose text renders without its header. It stays a card whatever happens to the
  # header: waiting for it, or told it is gone.
  def readable_card?(message)
    message.content_attributes['rich'].present? && message.content.present?
  end

  # History work shares the instance-wide slots the import takes (Inbound::ImportSlots):
  # Sidekiq's threads are one pool, so several inboxes draining at once would otherwise hold
  # every one of them and leave live traffic waiting, whatever queue the drains sit on. A
  # run that finds no slot is told to come back with `on_full`; one that gave its slot back
  # wakes an import batch that was waiting for it.
  def with_slot(on_full:, &)
    slots = Whatsapp::Session::Inbound::ImportSlots
    slots.with_slot(&)
    slots.top_up(into: Whatsapp::Session::HistoryImportJob.queue_name)
  rescue Whatsapp::Session::Inbound::ImportSlots::Full
    on_full.call
  end

  # Queues every pending file the inbox's consent now covers. For when it starts covering
  # more than it did: the switch turned back on, or the window widened. Files written while
  # it was off were never queued, and importing again does not write them again.
  def requeue(inbox)
    inbox.messages.where.missing(:attachments).where(created_at: cutoff(inbox.channel)..).find_each { |message| track(message) }
  end

  # One download, inline. Called from the drain and the conversation job, which pace
  # themselves; the button queues a MediaFetchJob instead, since a person is waiting on
  # that one file.
  def fetch(message)
    Whatsapp::Session::MediaFetchJob.new.perform(message, message.content_attributes['pending_media'], chat_for(message))
  end

  def enqueue(message)
    Whatsapp::Session::MediaFetchJob.perform_later(message, message.content_attributes['pending_media'], chat_for(message))
  end

  # The chat the history event carried, which is where the provider files the message. A
  # message imported before that was kept falls back to the contact: right for a group,
  # whose contact is the group, and resolved by the connector to the same chat when the
  # contact is known by its LID.
  def chat_for(message)
    message.content_attributes['pending_chat'] ||
      Whatsapp::Session::Model::Address.for_contact(message.conversation.contact)&.to_h
  end

  def queue_key(inbox) = "WHATSAPP::HISTORY_MEDIA::#{inbox.id}"

  # Run by the minute sweep. A queue or a rescan request with no drain behind it is left by
  # a drain that could not be queued: the importer that tracked those files has finished,
  # and a retry of it skips the messages it already wrote, so nothing else would ever come
  # back for them. `kick` does nothing for an inbox whose drain is queued or running.
  def resume_stranded
    ids = Redis::Alfred.with do |conn|
      %w[HISTORY_MEDIA HISTORY_MEDIA_REQUEUE].flat_map do |name|
        conn.scan_each(match: "WHATSAPP::#{name}::*").map { |key| key.split('::').last.to_i }
      end
    end
    Inbox.where(id: ids.uniq).find_each { |inbox| Whatsapp::Session::HistoryMediaJob.kick(inbox) }
  end
end
