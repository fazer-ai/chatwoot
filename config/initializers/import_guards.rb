# The guards that make Import::SilentWrite mean something.
#
# Declared here, and not as autoloaded classes, on purpose: a reloadable module handed to
# `prepend` is a new object after every reload, so the ancestor chain would grow one copy
# per edit in development. These are defined once at boot and re-prepended to whatever
# generation of the class `to_prepare` hands over, which Ruby ignores when the module is
# already in the chain.
#
# Prepended rather than edited into the classes themselves: all three are files the
# upstream sync rewrites, and a guard clause inside them is a conflict on every merge.
module ImportGuards
  # Everything that acts on the world outside this request. An imported message may never
  # reach any of it, at either level of the flag: history that fires an automation, posts
  # an outgoing webhook or notifies an agent is history pretending to be an arrival.
  #
  # Stopped at enqueue rather than inside EventDispatcherJob, because the flag is scoped
  # to the importing thread and the job runs on another one, where it would read as unset.
  module SilentAsyncDispatch
    def dispatch(event_name, timestamp, data)
      return if Import::SilentWrite.on?

      super
    end
  end

  # The two listeners that run in this thread. ActionCableListener is the push that moves
  # the operator's screen; AgentBotListener is a bot about to answer a message from June.
  # Under `:announce` the first is exactly what the import is for and the second is exactly
  # what it must not do, so the split is drawn by hand here instead of by the dispatcher.
  #
  # Wisper subscribes its listeners once, at boot, so there is no per-call listener set to
  # narrow: the announcing branch bypasses the publisher and calls the one listener it
  # allows, the same way the publisher would have. `respond_to?` because a listener only
  # implements the events it cares about, which is the check Wisper itself makes.
  module SilentSyncDispatch
    def dispatch(event_name, timestamp, data)
      return super unless Import::SilentWrite.on?
      return unless Import::SilentWrite.announce?

      event = Events::Base.new(event_name, timestamp, data)
      listener = ActionCableListener.instance
      listener.public_send(event.method_name, event) if listener.respond_to?(event.method_name)
    end
  end

  # What the dispatcher does not cover: reopening a resolved conversation, the message
  # template hooks (an out-of-office reply to a message from June), the outgoing send, the
  # contact activity stamp and the conversation activity stamp. The importer sets the
  # activity stamps itself, because the callback moves them to whatever it just wrote and
  # history is written oldest first.
  #
  # One of the seven is a message to the screen rather than an action, and under `:announce`
  # the gap needs it: without `message.created` the conversation card in the list updates
  # and the thread the operator has open stays empty, which is a worse place to stop than
  # not updating at all.
  #
  # Only the event is re-emitted, not `dispatch_create_events`, which wraps it in bookkeeping
  # this importer has taken over: the first-reply branch writes `first_reply_created_at` and
  # clears `waiting_since`, and the other branch recomputes `waiting_since` from a message
  # being written oldest first. Both would fight `settle` for the same columns.
  # The two things that decide where a conversation goes and what state it is in. Both are
  # archive-only, and the level is the point: under `:announce` the thread is a gap somebody
  # is waiting on, and a gap thread that is neither assigned nor statused is one nobody
  # works until they happen to reload -- the exact failure the announcing level exists to
  # prevent.
  #
  # Assignment does not travel through the dispatcher, so nothing above stops it. An archive
  # thread is created resolved, and a status change to resolved is what wakes the V2
  # assignment job: once per conversation, half a million times over a full import, each
  # asking the inbox to redistribute capacity it has no reason to redistribute. The V1 path
  # is worse -- it assigns the thread outright, so a decade of somebody's history lands in a
  # working agent's queue.
  #
  # The bot override is narrower than the callback that carries it. `determine_conversation_status`
  # also resolves a conversation whose contact is blocked, which is right at either level and
  # is not the importer's business to undo, so only the bot half is stopped: an inbox with an
  # agent bot starts its conversations `pending` and overrides the `resolved` an archive
  # importer asked for on purpose.
  module SilentAutoAssignment
    def run_auto_assignment
      return if Import::SilentWrite.archive?

      super
    end

    def set_active_bot_conversation
      return if Import::SilentWrite.archive?

      super
    end
  end

  # The two things a new contact does on its own, neither of which travels through the
  # dispatcher, so nothing above stops them. Each is one job per contact created.
  #
  # They sit at different levels because their reasons differ. Gravatar is a flood aimed at
  # a third party that never agreed to it, and a flood is what half a million contacts make
  # -- a gap sync creating one contact should fetch its avatar like any arrival, so that
  # guard is archive-only. The IP lookup resolves an address an imported contact does not
  # carry at either level, so it is stopped at both.
  #
  # `Message#reindex_for_search` is the one after-commit side effect deliberately left
  # alone. It is inert unless advanced search is configured, and guarding it would leave an
  # archive that exists to be searched silently absent from the index. A deployment that
  # turns advanced search on wants one bulk reindex after the import, not a job per row.
  module SilentGravatar
    def fetch_avatar_from_gravatar
      return if Import::SilentWrite.archive?

      super
    end

    def ip_lookup
      return if Import::SilentWrite.on?

      super
    end
  end

  # A scheduled message with `hold_on_reply` is a promise an agent made about the future:
  # if the customer writes back first, do not send it. An incoming row satisfying that test
  # is the whole trigger, and an imported one satisfies it the same way a live one does.
  #
  # Archive only, and the level carries the whole argument. Under `:announce` the row is a
  # real reply that arrived while the connection was down, and holding the follow-up is
  # exactly right -- the customer did answer, we just learned about it late. Under
  # `:archive` the row is years old, and `scheduled_at > created_at` is then true of every
  # pending scheduled message in the account: importing one old ticket would hold every
  # follow-up an agent has queued.
  module SilentScheduledMessages
    def hold_pending_scheduled_messages
      return if Import::SilentWrite.archive?

      super
    end
  end

  # A Company is created as a side effect of importing a contact with a business address,
  # and its own after_create_commit fetches a favicon off the domain. Enterprise only, and
  # reached through two callbacks in different models, so neither the dispatcher guards nor
  # the two on Contact see it.
  #
  # The same shape as Gravatar and the same level: the association is real information
  # about the contact and belongs in the archive, but one outbound request per company at a
  # third party that never agreed to it is a flood when the archive is a decade of mail.
  # A gap sync creating one company should fetch its favicon like any arrival.
  module SilentFavicon
    def fetch_favicon
      return if Import::SilentWrite.archive?

      super
    end
  end

  # One transcription job per audio attachment, enqueued straight from the Attachment's own
  # after_create_commit. Enterprise only, and it reaches neither the dispatcher guards nor
  # the ones on Message: the job is not an event and the attachment is not the message.
  #
  # Archive only, and the reason is money rather than noise. Transcription spends Captain
  # credits per file and rides the low-priority queue, so an archive carrying years of
  # forwarded voice notes drains the account's balance transcribing conversations that were
  # closed before the feature existed -- and crowds out the live traffic waiting behind it.
  # A gap sync recovering one voice note wants it transcribed like any arrival.
  module SilentTranscription
    def enqueue_audio_transcription
      return if Import::SilentWrite.archive?

      super
    end
  end

  module SilentMessageCallbacks
    def execute_after_create_commit_callbacks
      return super unless Import::SilentWrite.on?
      return unless Import::SilentWrite.announce?

      Rails.configuration.dispatcher.dispatch(
        Events::Types::MESSAGE_CREATED, Time.zone.now, message: self, performed_by: Current.executed_by
      )
    end
  end
end

Rails.application.config.to_prepare do
  SyncDispatcher.prepend(ImportGuards::SilentSyncDispatch)
  AsyncDispatcher.prepend(ImportGuards::SilentAsyncDispatch)
  Message.prepend(ImportGuards::SilentMessageCallbacks)
  Message.prepend(ImportGuards::SilentScheduledMessages)
  Conversation.prepend(ImportGuards::SilentAutoAssignment)
  Contact.prepend(ImportGuards::SilentGravatar)
  if ChatwootApp.enterprise?
    Company.prepend(ImportGuards::SilentFavicon)
    Attachment.prepend(ImportGuards::SilentTranscription)
  end
end
