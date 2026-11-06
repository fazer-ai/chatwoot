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

  # Where the writer's media fetch goes. A live message's file is fetched as always. An
  # imported one goes through the inbox's drain like every other history file, whether or
  # not it came with a reference: a job queued straight away would download it even after
  # the operator turned the option off or narrowed the window, which the drain checks
  # before every file. The importer tracks it right after writing it.
  def route(message, inbound, imported)
    return yield unless imported

    defer(message, inbound)
  end

  # A history file that came with a reference. It is marked the way a reference-less one
  # is, which is what the drain, the button and the conversation action look for, and the
  # reference is kept: it is how the provider finds the file when it is asked for.
  def defer(message, inbound)
    media = Whatsapp::Session::Inbound::MessageWriter.media_in(inbound)
    return if media&.ref.blank?

    message.with_lock do
      message.update!(content_attributes: message.content_attributes.merge(
        'is_unsupported' => true, Whatsapp::Session::Inbound::MessageAttributes::HISTORY_MEDIA => true,
        'pending_media' => media.to_h, 'pending_chat' => inbound.chat&.to_h
      ).compact)
    end
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
end
