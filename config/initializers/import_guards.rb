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
  # Assignment is the one side effect that does not travel through the dispatcher, so
  # nothing above stops it. A backfilled thread is created resolved, and a status change to
  # resolved is exactly what wakes the V2 assignment job -- once per conversation, half a
  # million times over a full import, each one asking the inbox to redistribute capacity it
  # has no reason to redistribute. The V1 path is worse: it assigns the thread outright, so
  # a decade of somebody's history lands in a working agent's queue.
  module SilentAutoAssignment
    def run_auto_assignment
      return if Import::SilentWrite.on?

      super
    end

    # An inbox with an agent bot starts its conversations `pending`, and the callback that
    # does it overrides whatever status the creator asked for. An importer asks for
    # `resolved` on purpose -- a thread born resolved fires no resolution event and files
    # into no report -- so on an inbox that happens to have a bot the whole archive would
    # land in the pending queue instead, assigned to the bot, with nothing in the importer
    # to say why.
    def determine_conversation_status
      return if Import::SilentWrite.on?

      super
    end
  end

  # The two things a new contact does on its own, neither of which travels through the
  # dispatcher, so nothing above stops them. Both are one job per contact created, which is
  # ordinary at the rate people write in and half a million jobs when a mailbox is replayed.
  #
  # Gravatar is a queue flood aimed at a third party that never agreed to it, and the avatar
  # is cosmetic: the next live message fills it in. The IP lookup is worse than useless --
  # an imported contact carries no IP for it to look up.
  #
  # `Message#reindex_for_search` is the one after-commit side effect deliberately left
  # alone. It is inert unless advanced search is configured, and guarding it would leave an
  # archive that exists to be searched silently absent from the index. A deployment that
  # turns advanced search on wants one bulk reindex after the import, not a job per row.
  module SilentGravatar
    def fetch_avatar_from_gravatar
      return if Import::SilentWrite.on?

      super
    end

    def ip_lookup
      return if Import::SilentWrite.on?

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
  Conversation.prepend(ImportGuards::SilentAutoAssignment)
  Contact.prepend(ImportGuards::SilentGravatar)
end
